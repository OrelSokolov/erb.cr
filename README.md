# erb.cr

Rails-compatible **ERB for Crystal**, compiled at build time. Templates
keep ERB syntax and are compiled into native render methods via a
`run()` template processor (the same trick as the stdlib's ECR) — no
runtime parsing, no runtime interpolation.

Extracted from [action_view.cr](https://github.com/OrelSokolov/action_view.cr),
where parity with the real ActionView 8.1.4 is verified with oracle
specs (151 examples, 0 failures).

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

## Rails semantics

- `<%= expr %>` auto-escapes `String`; a `SafeString` (the SafeBuffer
  analog — Crystal's `String` cannot be subclassed) is appended raw
- `<% stmt %>` is control code; `<%# ... %>` comments are dropped
- Erubi trim: a newline directly after a `<% %>` code tag is removed
- Block helpers work: `<%= helper do %> ... <% end %>` keeps the whole
  call as the escaped expression, the block body appends to the shared
  output buffer (the `capture`/`content_for` machinery)
- Layouts use `<%= yield %>`; partials get typed locals and
  collection rendering with a 0-based `<name>_counter`

The expression language inside the tags is **Crystal**, not Ruby.

## Installation

```yaml
dependencies:
  erb_cr:
    github: OrelSokolov/erb.cr
```

```sh
shards install
```

Requires Crystal >= 1.21.0; no other dependencies.

## Usage

Include `ERB::Rendering` and compile templates into methods:

```crystal
require "erb_cr"

class View
  include ERB::Rendering

  getter title : String

  def initialize(@title = "Hello & welcome")
  end

  compile_template "page", "app/views/page.html.erb"
end

View.new.page.to_s # template compiled into #page at build time
```

Layouts (the compiled method takes a block for `<%= yield %>`):

```crystal
compile_layout "application", "app/views/layouts/application.html.erb"

def render_in_layout(content : String) : String
  application { content }.to_s
end
```

Partials — locals are declared with types at compile time and become
real local variables inside the compiled method:

```crystal
compile_partials({
  "post" => {path: "app/views/_post.html.erb", locals: {"post" => Post}},
})

render("post", {"post" => post})                  # render partial:, locals:
render("post", collection: posts)                 # + post_counter, 0-based
render("post", collection: posts, spacer_template: "gap")
```

Output safety:

```crystal
"<b>x</b>".html_safe?          # => false
"<b>x</b>".html_safe           # => ERB::SafeString, appended raw by <%= %>
ERB::SafeString.new("<b>") + " plain" # SafeString#+ keeps the wrapper
```

## Why not stdlib ECR?

ECR does not escape `<%= %>`, has no safe-string contract, no block
helpers, no trim/partials machinery. erb.cr reconstructs the ERB slice
of Rails ActionView — including `capture`/`content_for` — behind a
compile-time pipeline.

## License

Part of the rails.cr monorepo experiments; see the repository.
