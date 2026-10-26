cask "pesto" do
  version "1.0.1"
  sha256 :no_check

  url "https://github.com/MichaelRo/copypesto/releases/download/v#{version}/Pesto-#{version}.dmg",
      verified: "github.com/MichaelRo/copypesto/"
  name "Pesto"
  desc "Native clipboard manager for macOS"
  homepage "https://copypesto.net"

  livecheck do
    url "https://copypesto.net/appcast.xml"
    strategy :sparkle
  end

  auto_updates true
  depends_on macos: ">= :sequoia"

  app "Pesto.app"

  zap trash: [
    "~/Library/Application Support/net.copypesto.pesto",
    "~/Library/Caches/net.copypesto.pesto",
    "~/Library/Preferences/net.copypesto.pesto.plist",
    "~/Library/Saved Application State/net.copypesto.pesto.savedState",
  ]
end
