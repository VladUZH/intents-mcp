# Formula for the project tap (VladUZH/homebrew-tap). DRAFT: url/sha256 are filled in when a
# release tag exists (GATE: public repo + tap publishing). Builds from source; no dependencies,
# so no network access is needed during the build.
class IntentsMcp < Formula
  desc "Expose your Mac's App Intents to AI agents as MCP tools, through Shortcuts"
  homepage "https://github.com/VladUZH/intents-mcp"
  url "https://github.com/VladUZH/intents-mcp/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  depends_on xcode: ["26.0", :build]
  depends_on macos: :tahoe
  uses_from_macos "swift" => :build

  def install
    system "swift", "build", "--disable-sandbox", *std_swift_args
    bin.install ".build/release/intents-mcp"
  end

  def caveats
    <<~EOS
      Enable tools, then add the server to your agent:
        intents-mcp enable reminders.add calendar.create-event
        claude mcp add mac -- #{opt_bin}/intents-mcp serve
        codex mcp add mac -- #{opt_bin}/intents-mcp serve
      Each tool needs one "Add Shortcut" click and one "Always Allow" on first run.
      Signing a shortcut uses your iCloud account; Apple receives a copy for validation.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/intents-mcp --version")
    ENV["INTENTS_MCP_HOME"] = testpath.to_s
    request = <<~JSON
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{"experimental":{"x":{}}}}}
      {"jsonrpc":"2.0","id":2,"method":"tools/list"}
    JSON
    output = pipe_output("#{bin}/intents-mcp serve", request, 0)
    assert_match '"protocolVersion":"2025-06-18"', output
    assert_match '"tools":[]', output
  end
end
