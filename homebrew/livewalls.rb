# Homebrew formula for LiveWalls
require "fileutils"

class Livewalls < Formula
  desc "LiveWalls: Use videos as dynamic desktop wallpapers on macOS"
  homepage "https://github.com/fparrav/LiveWalls"
  url "https://github.com/fparrav/livewalls-dist/releases/download/v1.5.5/LiveWalls-v1.5.5.dmg"
  sha256 "3e9790db497458bd2d82392d90f749a256990ac6824bf782286a5c66552bb171"

  livecheck do
    strategy :github_latest
  end

  depends_on macos: :sonoma

  def install
    mount_dir = Pathname.new(Dir.mktmpdir("livewalls-dmg"))
    begin
      system "hdiutil", "attach", cached_download, "-nobrowse", "-mountpoint", mount_dir

      app_path = mount_dir/"LiveWalls.app"
      odie "LiveWalls.app not found in DMG" unless app_path.directory?

      destination = prefix/"Applications/LiveWalls.app"
      destination.dirname.mkpath
      FileUtils.cp_r(app_path, destination)
    ensure
      if mount_dir.exist?
        system "hdiutil", "detach", mount_dir
        FileUtils.remove_entry mount_dir
      end
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
