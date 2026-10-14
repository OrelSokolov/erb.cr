# Rendering specs: syntax (escaping, control code, comments, trim,
# block helpers) and semantics (capture, content_for, layouts,
# partials with typed locals / collection + counter / spacer).

require "spec"
require "../src/erb_cr"

class TestView
  include ERB::Rendering

  getter title : String
  getter safe_thing : ERB::SafeString
  getter items : Array(String)
  getter flag : Bool

  def initialize(@title = "<b>", @safe_thing = ERB::SafeString.new("<i>ok</i>"),
                 @items = ["a", "b"], @flag = false)
  end

  def danger : String
    "&"
  end

  # Block helper — like Rails content_tag/form_with: `<%= %>`s inside
  # the block go to the capture buffer.
  def wrap(&) : ERB::SafeString
    ERB::SafeString.new("<w>#{capture { yield }}</w>")
  end

  compile_template "escapes_tpl", "#{__DIR__}/fixtures/escapes.html.erb"
  compile_template "control_tpl", "#{__DIR__}/fixtures/control.html.erb"
  compile_template "block_tpl", "#{__DIR__}/fixtures/block.html.erb"
  compile_template "cf_tpl", "#{__DIR__}/fixtures/content_for.html.erb"
  compile_layout "wrapped", "#{__DIR__}/fixtures/layout.html.erb"

  compile_partials({
    "item" => {path: "#{__DIR__}/fixtures/_item.html.erb", locals: {"item" => String, "item_counter" => Int32}},
    "chip" => {path: "#{__DIR__}/fixtures/_chip.html.erb",  locals: {"chip" => String}},
    "gap"  => {path: "#{__DIR__}/fixtures/_gap.html.erb",   locals: {} of String => Nil},
  })
end

VIEW = TestView.new

describe "output safety" do
  it "marks plain strings unsafe and html_safe strings safe" do
    "<b>hi</b>".html_safe?.should be_false
    safe = "<b>hi</b>".html_safe
    safe.should be_a(ERB::SafeString)
    safe.html_safe?.should be_true
    safe.raw.should eq("<b>hi</b>")
  end

  it "keeps the wrapper in SafeString#+" do
    result = ERB::SafeString.new("<b>") + " plain"
    result.should be_a(ERB::SafeString)
    result.to_s.should eq("<b> plain")
  end
end

describe "compiled templates" do
  it "escapes <%= %> Strings and appends SafeString raw" do
    VIEW.escapes_tpl.to_s.should eq("<h1>&lt;b&gt;</h1>\n<i>ok</i>\ndone\n")
  end

  it "runs control code, drops comments and applies Erubi trim" do
    VIEW.control_tpl.to_s.should eq("- a\n- b\ntail no")
  end

  it "keeps block helpers as the escaped expression" do
    VIEW.block_tpl.to_s.should eq("<w>Inner &amp;</w>")
  end

  it "stores content_for blocks out of band" do
    VIEW.cf_tpl.to_s.should eq("BODY\n")
    VIEW.content_for(:title).to_s.should eq("My Page")
    VIEW.content_for?(:title).should be_true
    VIEW.content_for?(:missing).should be_false
    VIEW.content_for(:missing).to_s.should eq("")
  end

  it "injects the block into a compiled layout via <%= yield %>" do
    VIEW.wrapped { "BODY" }.to_s.should eq("<html>BODY</html>\n")
    VIEW.wrapped { ERB::SafeString.new("<b>B</b>") }.to_s.should eq("<html><b>B</b></html>\n")
  end
end

describe "capture" do
  it "returns what the block appended and keeps a returned value" do
    VIEW.capture { "ret" }.should eq("ret")
    VIEW.capture { }.should eq("")
  end
end

describe "partials" do
  it "renders with typed locals" do
    VIEW.render("chip", {"chip" => "x & y"}).to_s.should eq("[x &amp; y]")
  end

  it "renders a collection with a 0-based counter" do
    VIEW.render("item", collection: ["a", "b"]).to_s.should eq("<li>a:0</li>\n<li>b:1</li>\n")
  end

  it "renders a collection with a spacer template" do
    VIEW.render("item", collection: ["a", "b"], spacer_template: "gap").to_s
      .should eq("<li>a:0</li>\n+<li>b:1</li>\n")
  end

  it "raises on a missing partial" do
    expect_raises(ArgumentError, /Missing partial/) do
      VIEW.render("nope", nil)
    end
  end
end
