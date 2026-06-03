cask "doumi" do
  version "0.1.1"
  sha256 arm:   "<ARM_SHA256>",
         intel: "<INTEL_SHA256>"

  url "https://github.com/xirtus/doumi/releases/download/v#{version}/Doumi-#{version}.dmg"
  name "Doumi"
  desc "Open-source file automation assistant for macOS — a free alternative to Hazel"
  homepage "https://github.com/xirtus/doumi"

  depends_on macos: ">= :sonoma"

  app "Doumi.app"

  zap trash: [
    "~/Library/Application Support/Doumi",
    "~/Library/Caches/Doumi",
    "~/Library/Preferences/com.xirtus.doumi.plist",
    "~/.config/doumi",
  ]
end
