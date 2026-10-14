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

path = ARGV[0]
input = File.read(path)
# Rails renders template sources verbatim (no whole-file chomp) — the
# only newline suppression is Erubi's trim: a newline directly after a
# CODE tag `<% ... %>` is removed (oracle: rails_hello root_page keeps
# the trailing text newline; posts_index loses the one after `<% end %>`).

i = 0
pending_do = 0 # open `<%= expr do %>` expressions: `end` must also close the paren
while open = input.index("<%", i)
  text = input[i...open]
  print "__erb_out ", text.inspect, "\n" unless text.empty?

  close = input.index("%>", open + 2)
  raise "Missing %> in #{path} after offset #{open}" unless close
  inner = input[open + 2...close]
  i = close + 2

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
    i += 1 if input[i]? == '\n'
  end
end
text = input[i..]
print "__erb_out ", text.inspect, "\n" unless text.empty?
