# Rendering pipeline: ERB-syntax templates compiled at build time into
# methods that append to an output buffer, with Rails semantics —
# `<%= %>` escapes unsafe strings, `<% %>` is control code, block
# helpers (`form_with do ... end`, `content_for do ... end`) work by
# appending to the shared buffer inside the block.
#
# The template compiler is `template_processor.cr`, executed through
# the macro `run()` mechanism (same trick as stdlib ECR).

module ERB
  module Rendering
    # Compiled template output goes here. Swapped by `capture` so
    # content_for blocks don't leak into the page.
    @__erb_buf : IO::Memory = IO::Memory.new
    @__erb_content : Hash(String, SafeString) = {} of String => SafeString

    # Raw append (template text, safe HTML).
    def __erb_out(value : String) : Nil
      @__erb_buf << value
    end

    def __erb_out(value : SafeString) : Nil
      @__erb_buf << value.raw
    end

    # Escaping append — what `<%= expr %>` compiles to.
    def __erb_esc(value : String) : Nil
      @__erb_buf << HTML.escape(value)
    end

    def __erb_esc(value : SafeString) : Nil
      @__erb_buf << value.raw
    end

    def __erb_esc(value) : Nil
      @__erb_buf << value.to_s
    end

    # Runs the block against a fresh buffer and returns what it wrote.
    def capture(&) : String
      outer = @__erb_buf
      @__erb_buf = IO::Memory.new
      result = yield
      captured = @__erb_buf.to_s
      @__erb_buf = outer
      # A block whose body only `<%= %>s` appends directly; a block
      # that returns a value without appending keeps that value.
      captured.empty? && result.is_a?(String | SafeString) ? result.to_s : captured
    end

    # content_for/provide: store a named content block for the layout.
    def content_for(key : String | Symbol, &) : Nil
      store_content(key.to_s, SafeString.new(capture { yield }), force: true)
    end

    def provide(key : String | Symbol, &) : Nil
      store_content(key.to_s, SafeString.new(capture { yield }), force: false)
    end

    def content_for?(key : String | Symbol) : Bool
      @__erb_content.has_key?(key.to_s)
    end

    private def store_content(key : String, value : SafeString, force : Bool) : Nil
      @__erb_content[key] = value if force || !@__erb_content[key]?
    end

    # `yield` / `yield :key` inside layouts.
    def content_for(key : String | Symbol) : SafeString
      @__erb_content[key.to_s]? || SafeString.new("")
    end

    # Compiles an ERB-syntax template into a method returning
    # SafeString. `path` is resolved from the compile-time working
    # directory (like stdlib ECR). `dedent: true` strips leading
    # whitespace of each line from literal text at compile time, so
    # indented sources render flat output (see template_processor.cr).
    #
    # Crystal allows redefining a method — a duplicate name would
    # silently shadow a handwritten helper (a runtime crash later,
    # like a nil'd accessor), so collisions fail the build instead.
    # Methods defined AFTER this macro call are not visible to the
    # guard ({% @type.methods %} only sees the type so far).
    macro compile_template(name, path, dedent = false)
      {% raise "compile_template: method '#{name.id}' is already defined in #{@type} — the compiled template would silently shadow it" if @type.methods.any? { |m| m.name.id == name.id } %}
      def {{ name.id }} : ERB::SafeString
        @__erb_buf = IO::Memory.new
        {{ run("./template_processor", path, dedent) }}
        ERB::SafeString.new(@__erb_buf.to_s)
      end
    end

    # Same, but the method takes a block: layouts use `<%= yield %>` /
    # `<%= yield :key %>` to inject the action's content.
    macro compile_layout(name, path, dedent = false)
      {% raise "compile_layout: method '#{name.id}' is already defined in #{@type} — the compiled layout would silently shadow it" if @type.methods.any? { |m| m.name.id == name.id } %}
      def {{ name.id }}(&) : ERB::SafeString
        @__erb_buf = IO::Memory.new
        {{ run("./template_processor", path, dedent) }}
        ERB::SafeString.new(@__erb_buf.to_s)
      end
    end

    # Compiles the class's partials and generates the runtime render
    # helpers. `partials` maps a partial name (as passed to `render`)
    # to a definition: `path` — the .erb file, `locals` — a
    # compile-time map of local variable name to its type:
    #
    #   compile_partials({
    #     "post" => {path: "app/views/_post.html.erb", locals: {"post" => Post}},
    #   })
    #
    # `dedent: true` applies the compile-time dedent mode (see
    # compile_template) to every partial in the map.
    #
    # Locals become real local variables inside the compiled method, so
    # templates reference them bare (`<%= post.title %>`), exactly like
    # Rails partials. Crystal forbids `Object` as a generic argument,
    # so the locals-hash value type is the union of all local types
    # (plus Int32 for the collection counter), deduplicated by name —
    # duplicate args inside Union(...) crash the compiler.
    macro compile_partials(partials, dedent = false)
      # Collect and dedupe (by name) the local types; Int32 is always
      # included — collection rendering passes a 0-based counter.
      {% local_types = [] of Nil %}
      {% for _name, defn in partials %}
        {% for _key, t in defn[:locals] %}
          {% local_types << t %}
        {% end %}
      {% end %}
      {% local_types << Int32 %}
      {% uniq = [] of Nil %}
      {% for t in local_types %}
        {% uniq << t unless uniq.map(&.stringify).includes?(t.stringify) %}
      {% end %}

      # The union goes through an alias: a macro-pasted `Union(...)`
      # used directly as a call-site restriction does not unify with
      # the same union written as a hash's value type when sibling
      # classes collapse to a common ancestor (e.g. two AR models) —
      # generics are invariant over distinct instantiations
      # (Crystal 1.21). Through the alias both sides resolve to one
      # type.
      alias ERBPartialLocal = Union({% for t in uniq %}{{ t.resolve }}, {% end %})

      {% for name, defn in partials %}
        def __erb_partial_{{ name.id.gsub(/[^a-zA-Z0-9_]/, "_").id }}({% for key, type in defn[:locals] %}{{ key.id }} : {{ type }}, {% end %}) : ERB::SafeString
          outer = @__erb_buf
          @__erb_buf = IO::Memory.new
          {{ run("./template_processor", defn[:path], dedent) }}
          result = @__erb_buf.to_s
          @__erb_buf = outer
          ERB::SafeString.new(result)
        end
      {% end %}

      # NOTE: the union must be pasted through resolved TypeNodes and
      # the dispatcher must be called with a hash already typed as the
      # union — a macro-pasted union used as a call-site restriction
      # binds to the argument's own value type, breaking member casts
      # (Crystal 1.21; hash literals don't upcast to union values).
      def __erb_render_partial(name : String, locals : Hash(String, ERBPartialLocal)) : ERB::SafeString
        case name
        {% for name, defn in partials %}
        when {{ name }} then __erb_partial_{{ name.id.gsub(/[^a-zA-Z0-9_]/, "_").id }}({% for key, type in defn[:locals] %}locals[{{ key }}].as({{ type }}), {% end %})
        {% end %}
        else raise ArgumentError.new("Missing partial #{name.inspect}")
        end
      end

      # render partial: "name", locals: {...}
      #
      # NOTE: unlike Ruby, the locals hash uses Crystal literal syntax —
      # `locals: {"post" => post}`, not `locals: {post: post}` (a Ruby
      # hash literal is a NamedTuple in Crystal). Documented deviation.
      def render(partial : String, locals : Hash? = nil) : ERB::SafeString
        h = {} of String => ERBPartialLocal
        locals.try { |l| l.each { |k, v| h[k.to_s] = v } }
        __erb_render_partial(partial, h)
      end

      # render partial: "name", collection: [...] [, as_local: "item"]
      # [, spacer_template: "gap"]
      #
      # The local name defaults to the partial's basename (Rails
      # semantics); each item also gets a `<name>_counter` local,
      # 0-based (Rails 7.1+ behavior).
      def render(partial : String, *, collection : Array, as_local : String? = nil,
                 locals : Hash? = nil, spacer_template : String? = nil) : ERB::SafeString
        key = as_local || File.basename(partial)
        ERB::SafeString.new(String.build do |buf|
          collection.each_with_index do |item, i|
            if spacer_template && i > 0
              buf << __erb_render_partial(spacer_template, {} of String => ERBPartialLocal).raw
            end
            l = {} of String => ERBPartialLocal
            locals.try { |ls| ls.each { |k, v| l[k.to_s] = v } }
            l[key] = item
            l["#{key}_counter"] = i
            buf << __erb_render_partial(partial, l).raw
          end
        end)
      end
    end

    # Renders a compiled template method inside a swapped buffer —
    # used for layouts (`content = view.__erb_render_action` then
    # layout's `yield` returns it).
    def __erb_render_with_content(name : String | Symbol) : ERB::SafeString
      @__erb_content[name.to_s]? || SafeString.new("")
    end
  end
end
