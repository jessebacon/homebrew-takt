# Starter formula for the private `takt` repo distributed via a public
# `homebrew-takt` tap.
#
# Note: the formula is named `takt-cli` (not `takt`) because `takt` is
# already taken in homebrew-core by a music-programming language, and
# homebrew-core always wins over personal taps. The installed binary is
# still `takt` — only the `brew install` command differs.
#
# Usage:
#   1. Copy this file into your tap repo at `Formula/takt-cli.rb`.
#   2. On every release, bump `version`, `url`, and `sha256` (the release
#      workflow prints the exact snippet to paste).
#   3. Commit and push. Users run `brew upgrade takt-cli`.
#
# First-time install for users:
#   export HOMEBREW_GITHUB_API_TOKEN=<a PAT with `repo` scope>
#   brew tap jessebacon/takt
#   brew install takt-cli
#
# The token is required because the `takt` source repo is private but this
# tap is public. The `GitHubPrivateRepositoryReleaseDownloadStrategy` helper
# reads `HOMEBREW_GITHUB_API_TOKEN` and uses it to download the release asset.

require "download_strategy"

class TaktCli < Formula
  desc "AI-powered development orchestration"
  homepage "https://github.com/jessebacon/takt"
  url "https://github.com/jessebacon/takt/releases/download/v0.1.0/takt-v0.1.0-macos-universal.tar.gz",
      using: GitHubPrivateRepositoryReleaseDownloadStrategy
  sha256 "REPLACE_WITH_SHA_FROM_RELEASE_WORKFLOW"
  version "0.1.0"
  license "MIT"

  # The Rust binary is self-contained. Python is only needed for the agent
  # sidecar, which bootstraps its own venv at `~/.takt/venv` on first run.
  depends_on "python@3.12"

  def install
    # Rust binary
    libexec.install "takt" => "takt-bin"

    # Python sidecar + pinned deps live in libexec; the Rust binary finds
    # them through env vars set by the wrapper below.
    libexec.install "takt_agent.py"
    libexec.install "requirements.txt"

    # Wrapper in bin/ sets the sidecar + requirements paths so the installed
    # binary doesn't rely on compile-time CARGO_MANIFEST_DIR, which points
    # to the build machine.
    (bin/"takt").write <<~SH
      #!/bin/bash
      export TAKT_AGENT_SIDECAR="#{libexec}/takt_agent.py"
      export TAKT_AGENT_REQUIREMENTS="#{libexec}/requirements.txt"
      exec "#{libexec}/takt-bin" "$@"
    SH
    (bin/"takt").chmod 0755
  end

  def caveats
    <<~EOS
      On first pipeline execution, takt will create a Python venv at
      ~/.takt/venv and install its sidecar dependencies. This requires
      network access and takes ~30 seconds.

      You can trigger the bootstrap manually with:
        takt doctor

      API keys live in ~/.takt/config.json or ~/.takt/.env:
        ANTHROPIC_API_KEY=sk-ant-...
        LINEAR_API_KEY=lin_api_...   # only if using Linear integration

      This tap pulls release assets from a private GitHub repo. You must
      export HOMEBREW_GITHUB_API_TOKEN (a PAT with `repo` scope) before
      running `brew install` or `brew upgrade`.
    EOS
  end

  test do
    assert_match "takt", shell_output("#{bin}/takt --version")
    # `takt examples` doesn't touch the network or config — good smoke test.
    assert_match "Available topics", shell_output("#{bin}/takt examples")
  end
end
