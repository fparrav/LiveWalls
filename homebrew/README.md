# Homebrew Formula for LiveWalls

This directory contains the Homebrew formula for LiveWalls, a macOS application that allows users to set videos as dynamic desktop wallpapers.

## Installation

### Method 1: Using the Official Tap (Recommended)
```bash
brew tap fparrav/livewalls
brew install livewalls
```

### Method 2: Direct Installation
```bash
brew install --HEAD https://raw.githubusercontent.com/fparrav/LiveWalls/main/homebrew/livewalls.rb
```

## Troubleshooting

If you encounter issues with the tap, try:

1. **Update Homebrew**:
```bash
brew update
```

2. **Clear Homebrew cache**:
```bash
brew cleanup
```

3. **If the formula is not found, use direct installation**:
```bash
brew install --HEAD https://raw.githubusercontent.com/fparrav/LiveWalls/main/homebrew/livewalls.rb
```

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode command line tools

## Configuration

After installation, LiveWalls will be installed to:
```
/Applications/LiveWalls.app
```

## Security Notes

LiveWalls is distributed without Apple Developer signature. When first opening the app, macOS may prompt you to grant accessibility permissions.

To remove quarantine attributes (if needed):
```bash
xattr -d com.apple.quarantine /Applications/LiveWalls.app
```

## Support

For issues with the Homebrew formula, please check:
1. The [LiveWalls GitHub repository](https://github.com/fparrav/LiveWalls)
2. [Homebrew documentation](https://docs.brew.sh)
