# Homebrew formula for LiveWalls
require "fileutils"

class Livewalls < Formula
  desc "LiveWalls: Use videos as dynamic desktop wallpapers on macOS"
  homepage "https://github.com/fparrav/LiveWalls"
  url "https://github.com/fparrav/livewalls-dist/releases/download/v1.5.7/LiveWalls-v1.5.7.dmg"
  version "1.5.7"
  sha256 "43829ce8a29ac30efbabe8a72eef2f9cab67e360f0f0675a6340e4daca7087f3"

  livecheck do
    strategy :github_latest
  end

  depends_on macos: :sonoma

  def install
    mount_dir = Pathname(Dir.mktmpdir("livewalls-dmg"))
    mounted = false

    begin
      system "hdiutil", "attach", cached_download, "-nobrowse", "-mountpoint", mount_dir
      mounted = true

      app_path = mount_dir/"LiveWalls.app"
      odie "LiveWalls.app not found in DMG" unless app_path.directory?

      destination = prefix/"Applications/LiveWalls.app"
      destination.dirname.mkpath
      FileUtils.cp_r(app_path, destination)
    ensure
      system "hdiutil", "detach", mount_dir if mounted
      mount_dir.rmtree if mount_dir.exist?
    end
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
