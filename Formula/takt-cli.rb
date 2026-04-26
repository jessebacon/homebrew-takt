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
#   export HOMEBREW_GITHUB_API_TOKEN=<a PAT with `repo` scope or a
#       fine-grained PAT with Contents: Read-only on the takt repo>
#   brew tap jessebacon/takt
#   brew install takt-cli
#
# The token is required because the `takt` source repo is private but this
# tap is public. The custom download strategy below reads
# `HOMEBREW_GITHUB_API_TOKEN` and uses it to authenticate against the
# GitHub API when fetching the release asset.

require "download_strategy"

# Inline download strategy for private GitHub release assets.
#
# Homebrew used to ship this as a built-in, but it was removed — formulas
# that need it must define it locally. Downloads the release asset via the
# GitHub API (`/repos/:owner/:repo/releases/assets/:id`) using the caller's
# HOMEBREW_GITHUB_API_TOKEN for auth.
class GitHubPrivateRepositoryReleaseDownloadStrategy < CurlDownloadStrategy
  URL_PATTERN = %r{^https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/(\S+)$}

  def initialize(url, name, version, **meta)
    super
    parse_url_pattern
    set_github_token
  end

  def parse_url_pattern
    match = @url.match(URL_PATTERN)
    raise CurlDownloadStrategyError, "Invalid GitHub release URL: #{@url}" unless match

    _, @owner, @repo, @tag, @filename = *match
  end

  def set_github_token
    @github_token = ENV["HOMEBREW_GITHUB_API_TOKEN"]
    return if @github_token && !@github_token.empty?

    raise CurlDownloadStrategyError,
          "HOMEBREW_GITHUB_API_TOKEN must be set to install from a private GitHub repo."
  end

  def _fetch(url:, resolved_url:, timeout:)
    asset_url = "https://api.github.com/repos/#{@owner}/#{@repo}/releases/assets/#{asset_id}"
    curl_download asset_url,
                  "--header", "Accept: application/octet-stream",
                  "--header", "Authorization: token #{@github_token}",
                  to: temporary_path,
                  timeout: timeout
  end

  private

  def asset_id
    release_url = "https://api.github.com/repos/#{@owner}/#{@repo}/releases/tags/#{@tag}"
    headers = [
      "--header", "Accept: application/vnd.github+json",
      "--header", "Authorization: token #{@github_token}",
    ]
    output, _, status = curl_output(*headers, release_url)
    raise CurlDownloadStrategyError, "Failed to fetch release metadata for #{@tag}" unless status.success?

    release = JSON.parse(output)
    asset = release["assets"]&.find { |a| a["name"] == @filename }
    raise CurlDownloadStrategyError, "Release asset #{@filename} not found in #{@tag}" unless asset

    asset["id"]
  end
end

class TaktCli < Formula
  desc "AI-powered development orchestration"
  homepage "https://github.com/jessebacon/takt"
  url "https://github.com/jessebacon/takt/releases/download/v0.1.6/takt-v0.1.6-macos-universal.tar.gz",
      using: GitHubPrivateRepositoryReleaseDownloadStrategy
  sha256 "346b99a552c9ecc99097b0dd8f9c76be01d3cd591942802d8539238c803d2200"
  version "0.1.6"
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

    # Pre-built documentation site (served by `takt docs`).
    libexec.install "docs"

    # Wrapper in bin/ sets the sidecar, requirements, and docs paths so the
    # installed binary doesn't rely on compile-time CARGO_MANIFEST_DIR,
    # which points to the build machine.
    (bin/"takt").write <<~SH
      #!/bin/bash
      export TAKT_AGENT_SIDECAR="#{libexec}/takt_agent.py"
      export TAKT_AGENT_REQUIREMENTS="#{libexec}/requirements.txt"
      export TAKT_DOCS_DIR="#{libexec}/docs"
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
      export HOMEBREW_GITHUB_API_TOKEN (a PAT with `repo` scope, or a
      fine-grained PAT with Contents: Read-only on the takt repo) before
      running `brew install` or `brew upgrade`.
    EOS
  end

  test do
    assert_match "takt", shell_output("#{bin}/takt --version")
    # `takt examples` doesn't touch the network or config — good smoke test.
    assert_match "Available topics", shell_output("#{bin}/takt examples")
  end
end
