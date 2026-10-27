# Template compiler entry point (compile-time tool). Invoked via the
# macro `run()` from rendering.cr — prints Crystal statements that
# append to the view's output buffer:
#
#   text            ->  __erb_out "..."
#   <%= expr %>     ->  __erb_esc(expr)
#   <% stmt %>      ->  stmt            (control code, may open blocks)
#   <%# ... %>      ->  comment (dropped)
#
# `<%= expr %>` where expr opens a `do ... end` block works naturally:
# the statements between the tags end up inside the block, `<% end %>`
# closes it, and the whole call remains the argument of `__erb_esc`.
#
# Optional dedent mode (ARGV[1] == "true", set by `compile_template
# ... dedent: true`): leading whitespace of each line is dropped from
# literal text at compile time (`\n[ \t]+` → `\n`), so the source may
# be indented while the rendered output stays flat. Whitespace on the
# same line after a tag is preserved; when Erubi trim just ate the
# newline after a code tag, the next segment starts a new source line,
# so its leading whitespace run is stripped as well.

path = ARGV[0]
dedent = ARGV[1]? == "true"
input = File.read(path)

def literal(text : String, dedent : Bool, at_line_start : Bool) : String
  return text unless dedent
  text = text.sub(/\A[ \t]+/, "") if at_line_start
  text.gsub(/\n[ \t]+/, "\n")
end
# Rails renders template sources verbatim (no whole-file chomp) — the
# only newline suppression is Erubi's trim: a newline directly after a
# CODE tag `<% ... %>` is removed (oracle: rails_hello root_page keeps
# the trailing text newline; posts_index loses the one after `<% end %>`).

i = 0
# Stack of constructs opened inside the template: :paren for
# `<%= expr do %>` (its `end` must also close the `__erb_esc(` paren),
# :plain for control-flow blocks (`if`/`unless`/`case`/`begin`/`do`).
# An `<% end %>` always closes the innermost construct — matching them
# with a flat counter mis-parses templates where a control block wraps
# a block-helper call (rooms/_form).
open_blocks = [] of Symbol
at_line_start = false
while open = input.index("<%", i)
  text = input[i...open]
  print "__erb_out ", literal(text, dedent, at_line_start).inspect, "\n" unless text.empty?

  close = input.index("%>", open + 2)
  raise "Missing %> in #{path} after offset #{open}" unless close
  inner = input[open + 2...close]
  i = close + 2
  at_line_start = false

  if inner.starts_with?("#")
    next # comment
  elsif inner.starts_with?("=")
    expr = inner[1..].strip
    # `yield` in layouts injects already-rendered (safe) content.
    # `yield :key` reads the captured content_for block (the compiled
    # layout method's block takes no arguments, so `yield :key` cannot
    # pass the key through).
    if expr =~ /\Ayield\s+(:[a-zA-Z_][a-zA-Z0-9_]*)\s*\z/
      print "__erb_out( content_for(#{$1}) )\n"
    elsif expr.starts_with?("yield")
      print "__erb_out( ", expr, " )\n"
    elsif expr.ends_with?("do") || expr =~ /do\s+\|[^|]*\|\s*$/
      print "__erb_esc( ", expr, "\n"
      open_blocks << :paren
    else
      print "__erb_esc( ", expr, " )\n"
    end
  else
    code = inner.strip
    if code == "end" && (top = open_blocks.pop?)
      print top == :paren ? "end )" : "end", "\n"
    else
      print inner, "\n"
      # Statement-initial keywords only — trailing `if`/`unless`
      # modifiers don't open blocks; `do` as the last token
      # (iterator blocks) does.
      open_blocks << :plain if code =~ /\A(if|unless|case|begin|while|until)\b/
      open_blocks << :plain if code =~ /\bdo\s*(\|[^|]*\|)?\z/
    end
    # Erubi trim: drop one newline right after a code tag.
    if input[i]? == '\n'
      i += 1
      at_line_start = true
    end
  end
end
text = input[i..]
print "__erb_out ", literal(text, dedent, at_line_start).inspect, "\n" unless text.empty?
