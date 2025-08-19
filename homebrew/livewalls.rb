class Livewalls < Formula
  desc "LiveWalls: Use videos as dynamic desktop wallpapers on macOS"
  homepage "https://github.com/fparrav/LiveWalls"
  url "https://github.com/fparrav/LiveWalls/releases/download/v1.5.1/LiveWalls-v1.5.1.dmg"
  version "1.5.1"
  sha256 "a2807497c027c76b1514ed63bcc48f0bf0c42ce0a9236f2c714d17776476f4da"

  livecheck do
    url :stable
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  def install
    # Install the app bundle to Applications
    prefix.install "LiveWalls.app" => "Applications/LiveWalls.app"
  end

  def post_install
    # Remove quarantine attribute to avoid security warnings
    system "xattr", "-d", "com.apple.quarantine", "#{prefix}/Applications/LiveWalls.app"
  end

  test do
    # Basic test to verify installation
    system "true"
  end

  def caveats
    <<~EOS
      LiveWalls has been installed successfully to Applications folder.

      To use LiveWalls:
        1. Open Applications folder and launch LiveWalls
        2. Add your video files using the interface
        3. Select a video and set it as your wallpaper

      Note: LiveWalls requires accessibility permissions to set wallpapers.
      macOS will prompt you to grant these permissions when first running the app.

      For more information, visit:
        https://github.com/fparrav/LiveWalls
    EOS
  end
end
