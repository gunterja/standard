# All of these requires were needed because `ruby_lsp/internal` mutates rubocop
# in a way that breaks test/standard/cli_test.rb
require "sorbet-runtime"
require "language_server-protocol"
require "ruby_lsp/base_server"
require "ruby_lsp/server"
require "ruby_lsp/requests"
require "ruby_lsp/addon"
require "ruby_lsp/utils"
require "ruby_lsp/store"
require "ruby_lsp/document"
require "ruby_lsp/global_state"
require "core_ext/uri"
require "ruby_indexer/ruby_indexer"
require "ruby_lsp/ruby_document"
require "prism"
require "ruby_lsp/standard/addon"

require_relative "test_helper"

class RubyLspAddonTest < UnitTest
  def setup
    @addon = RubyLsp::Standard::Addon.new
    super
  end

  def test_name
    assert_equal "Standard Ruby", @addon.name
  end

  def test_diagnostic
    source = <<~RUBY
      s = 'hello'
      puts s
    RUBY
    with_server(source, "simple.rb") do |server, uri|
      server.process_message(
        id: 2,
        method: "textDocument/diagnostic",
        params: {
          textDocument: {
            uri: uri
          }
        }
      )

      result = server.pop_response

      assert_instance_of(RubyLsp::Result, result)
      assert_equal "full", result.response.kind
      assert_equal 1, result.response.items.size
      item = result.response.items.first
      assert_equal({line: 0, character: 4}, item.range.start.to_hash)
      assert_equal({line: 0, character: 10}, item.range.end.to_hash)
      assert_equal RubyLsp::Constant::DiagnosticSeverity::INFORMATION, item.severity
      assert_equal "Style/StringLiterals", item.code
      assert_equal "https://docs.rubocop.org/rubocop/cops_style.html#stylestringliterals", item.code_description.href
      assert_equal "Standard Ruby", item.source
      assert_equal "Prefer double-quoted strings unless you need single quotes to avoid extra backslashes for escaping.", item.message
    end
  end

  def test_format
    source = <<~RUBY
      s = 'hello'
      puts s
    RUBY
    with_server(source, "simple.rb") do |server, uri|
      server.process_message(
        id: 2,
        method: "textDocument/formatting",
        params: {textDocument: {uri: uri}, position: {line: 0, character: 0}}
      )

      result = server.pop_response

      assert_instance_of(RubyLsp::Result, result)
      assert 1, result.response.size
      assert_equal <<~RUBY, result.response.first.new_text
        s = "hello"
        puts s
      RUBY
    end
  end

  private

  # Lifted from here, because we need to override the formatter to "standard" in the test helper:
  # https://github.com/Shopify/ruby-lsp/blob/4c1906172add4d5c39c35d3396aa29c768bfb898/lib/ruby_lsp/test_helper.rb#L20
  def with_server(source = nil, path = "fake.rb", pwd: "test/fixture/ruby_lsp", stub_no_typechecker: false, load_addons: true,
    &block)
    Dir.chdir pwd do
      server = RubyLsp::Server.new(test_mode: true)
      uri = Kernel.URI(File.join(server.global_state.workspace_path, path))
      server.global_state.formatter = "standard"
      server.global_state.instance_variable_set(:@linters, ["standard"])
      server.global_state.stubs(:typechecker).returns(false) if stub_no_typechecker

      if source
        server.process_message({
          method: "textDocument/didOpen",
          params: {
            textDocument: {
              uri: uri,
              text: source,
              version: 1
            }
          }
        })
      end

      server.global_state.index.index_single(
        RubyIndexer::IndexablePath.new(nil, uri.to_standardized_path),
        source
      )
      server.load_addons if load_addons
      block.call(server, uri)
    end
  ensure
    if load_addons
      RubyLsp::Addon.addons.each(&:deactivate)
      RubyLsp::Addon.addons.clear
    end
  end
end
