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
pending_do = 0 # open `<%= expr do %>` expressions: `end` must also close the paren
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
    if expr.starts_with?("yield")
      print "__erb_out( ", expr, " )\n"
    elsif expr.ends_with?("do") || expr =~ /do\s+\|[^|]*\|\s*$/
      print "__erb_esc( ", expr, "\n"
      pending_do += 1
    else
      print "__erb_esc( ", expr, " )\n"
    end
  else
    code = inner.strip
    if code == "end" && pending_do > 0
      print "end )\n"
      pending_do -= 1
    else
      print inner, "\n"
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
