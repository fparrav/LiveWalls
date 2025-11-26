import SwiftUI

/// Reusable glass card component with liquid glass aesthetic
struct GlassCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12
    var material: Material = .ultraThinMaterial
    var shadowRadius: CGFloat = 8
    var borderColor: Color = .white.opacity(0.15)
    var borderWidth: CGFloat = 1
    
    init(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 12,
        material: Material = .ultraThinMaterial,
        shadowRadius: CGFloat = 8,
        borderColor: Color = .white.opacity(0.15),
        borderWidth: CGFloat = 1,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.material = material
        self.shadowRadius = shadowRadius
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(material)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: .black.opacity(0.1), radius: shadowRadius, x: 0, y: 4)
    }
}

/// Hoverable glass card with scale and glow effects
struct HoverableGlassCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12
    var material: Material = .ultraThinMaterial
    var shadowRadius: CGFloat = 8
    var borderColor: Color = .white.opacity(0.15)
    var borderWidth: CGFloat = 1
    var hoverScale: CGFloat = 1.02
    var hoverShadowRadius: CGFloat = 16
    
    @State private var isHovered = false
    
    init(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 12,
        material: Material = .ultraThinMaterial,
        shadowRadius: CGFloat = 8,
        borderColor: Color = .white.opacity(0.15),
        borderWidth: CGFloat = 1,
        hoverScale: CGFloat = 1.02,
        hoverShadowRadius: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.material = material
        self.shadowRadius = shadowRadius
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.hoverScale = hoverScale
        self.hoverShadowRadius = hoverShadowRadius
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(material)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isHovered ? borderColor.opacity(0.3) : borderColor, lineWidth: borderWidth)
            )
            .shadow(
                color: .black.opacity(isHovered ? 0.15 : 0.1),
                radius: isHovered ? hoverShadowRadius : shadowRadius,
                x: 0,
                y: isHovered ? 6 : 4
            )
            .scaleEffect(isHovered ? hoverScale : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Glass card with accent border for selected state
struct SelectableGlassCard<Content: View>: View {
    let content: Content
    let isSelected: Bool
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12
    var material: Material = .ultraThinMaterial
    var shadowRadius: CGFloat = 8
    var normalBorderColor: Color = .white.opacity(0.15)
    var selectedBorderColor: Color = .accentColor
    var borderWidth: CGFloat = 1
    var selectedBorderWidth: CGFloat = 2
    
    init(
        isSelected: Bool,
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 12,
        material: Material = .ultraThinMaterial,
        shadowRadius: CGFloat = 8,
        normalBorderColor: Color = .white.opacity(0.15),
        selectedBorderColor: Color = .accentColor,
        borderWidth: CGFloat = 1,
        selectedBorderWidth: CGFloat = 2,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.material = material
        self.shadowRadius = shadowRadius
        self.normalBorderColor = normalBorderColor
        self.selectedBorderColor = selectedBorderColor
        self.borderWidth = borderWidth
        self.selectedBorderWidth = selectedBorderWidth
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(material)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isSelected ? selectedBorderColor : normalBorderColor,
                        lineWidth: isSelected ? selectedBorderWidth : borderWidth
                    )
            )
            .shadow(
                color: isSelected ? selectedBorderColor.opacity(0.3) : .black.opacity(0.1),
                radius: shadowRadius,
                x: 0,
                y: 4
            )
            .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Preview Provider

#Preview("Glass Card") {
    VStack(spacing: 20) {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Basic Glass Card")
                    .font(.headline)
                Text("Ultra-thin material with border and shadow")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        
        HoverableGlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hoverable Glass Card")
                    .font(.headline)
                Text("Hover to see scale and shadow effects")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        
        SelectableGlassCard(isSelected: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Selected Glass Card")
                    .font(.headline)
                Text("Shows accent border when selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        
        SelectableGlassCard(isSelected: false) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Unselected Glass Card")
                    .font(.headline)
                Text("Normal border when not selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    .frame(width: 400)
    .padding()
    .background(Color.gray.opacity(0.2))
}
