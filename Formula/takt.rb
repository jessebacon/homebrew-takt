  class Takt < Formula
    desc "AI-powered development orchestration"
    homepage "https://github.com/jessebacon/takt"
    url "https://github.com/jessebacon/takt/releases/download/v0.1.0/takt-v0.1.
  0-macos-universal.tar.gz"
    sha256 "fe0fe1d62696b8b6f553e56c9f9f81f4d51568ca07e392a45e641cf532c0ebd6"
    version "0.1.0"
    license "MIT"  # or whatever you pick

    def install
      bin.install "takt"
    end

    test do
      assert_match "takt", shell_output("#{bin}/takt --version")
    end
  end
