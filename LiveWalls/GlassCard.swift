import SwiftUI

/// Central namespace for the "liquid glass" visual language metrics.
///
/// Defines the shared spacing grid, control sizes, corner radii, divider
/// treatment, and accent color used by every floating glass panel
/// (main window controls, settings, status bar menu, and about window).
/// Satisfies the 8-point spacing grid and macOS HIG control metrics so the
/// values are defined once instead of duplicated as magic numbers per view.
enum LiquidGlassMetrics {
    /// 20px outer margin between a panel/edge and the window edge.
    static let outerMargin: CGFloat = 20
    /// 36px height for the top-row pill controls (traffic lights, transport, library toggle).
    static let pillHeight: CGFloat = 36
    /// 320px width for the library rail in the main window.
    static let railWidth: CGFloat = 320
    /// 20px corner radius on cards and rails.
    static let cardCornerRadius: CGFloat = 20
    /// 12px corner radius on inner controls.
    static let controlCornerRadius: CGFloat = 12
    /// 1px divider line width.
    static let dividerWidth: CGFloat = 1
    /// Divider color opacity (14–16% range, per the mockup design).
    static let dividerOpacity: CGFloat = 0.15
    /// Divider overlay color (white at the shared opacity).
    static let dividerColor: Color = .white.opacity(dividerOpacity)
    /// Accent color (red-orange `#EC3013`) used for active/primary state.
    static let accentColor: Color = Color(red: 0xEC / 255.0, green: 0x30 / 255.0, blue: 0x13 / 255.0)
    /// Horizontal space reserved at the top-leading window corner for the
    /// native traffic-light window buttons (close/minimize/zoom), which float
    /// over the transparent title bar. Any top-leading floating control must
    /// start past this clearance so it doesn't sit under/overlap them.
    static let trafficLightsClearance: CGFloat = 78
    /// 44px height for the bottom rotation bar -- slightly taller than the
    /// 36px top-row pills, since it reads as the main window's persistent
    /// control strip rather than a transient floating pill.
    static let bottomBarHeight: CGFloat = 44
    /// The bottom rotation bar spans this fraction of the window's width
    /// (centered) rather than stretching edge to edge like the top-row pills,
    /// so it reads as a distinct, narrower control strip.
    static let bottomBarWidthRatio: CGFloat = 0.7
}

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

// MARK: - Light Glass Surface Modifier

/// Light "glass" surface treatment for controls that float over the live video
/// preview in the main window.
///
/// Applies a translucent light `Material` background, a subtle light border, and a
/// soft outer shadow. Metrics are sourced from `LiquidGlassMetrics` so the surface
/// stays consistent with the shared 8-point spacing grid and macOS HIG control
/// metrics instead of duplicating magic numbers per call site.
///
/// This is the light counterpart to the glass-dark style used by panels shown
/// over opaque backgrounds (settings, status bar menu, about window).
struct GlassSurfaceModifier: ViewModifier {
     /// Corner radius for floating controls (12px inner controls metric).
    var cornerRadius: CGFloat = LiquidGlassMetrics.controlCornerRadius
    /// Base border color (specular gradient is derived from this at top/bottom opacities).
    var borderColor: Color = .white
    /// Border opacity at the top edge (brightest point of the specular gradient).
    var borderTopOpacity: CGFloat = 0.55
    /// Border opacity at the bottom edge (faded point of the specular gradient).
    var borderBottomOpacity: CGFloat = 0.08
    /// Border line width.
    var borderWidth: CGFloat = LiquidGlassMetrics.dividerWidth
    /// Outer (ambient) shadow radius.
    var shadowRadius: CGFloat = 8
    /// Outer (ambient) shadow vertical offset.
    var shadowY: CGFloat = 4
    /// Base translucency material used behind the control.
    var material: Material = .ultraThinMaterial

    func body(content: Content) -> some View {
        content
             .background(material)
             .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.10), Color.white.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
             )
             .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
             .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                     .strokeBorder(
                        LinearGradient(
                            colors: [borderColor.opacity(borderTopOpacity), borderColor.opacity(borderBottomOpacity)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: borderWidth
                     )
             )
             // Contact shadow: tight, low-radius, close to the surface.
             .shadow(color: .black.opacity(0.20), radius: 1, x: 0, y: 1)
             // Ambient shadow: soft, wider spread.
             .shadow(color: .black.opacity(0.10), radius: shadowRadius, x: 0, y: shadowY)
    }
}

extension View {
    /// Applies the light glass surface treatment (translucent blur, subtle light
    /// border, soft outer shadow) to a control floating over the video preview.
    ///
    /// Usage example:
    /// ```swift
    /// HStack { /* transport controls */ }
    ///     .glassSurface()
    /// ```
    ///
    /// - Parameters:
    ///   - cornerRadius: Outer corner radius; defaults to the shared control metric.
    ///   - borderColor: Base border color the specular gradient is derived from; defaults to white.
    ///   - borderTopOpacity: Border opacity at the top edge (brightest point); defaults to 55%.
    ///   - borderBottomOpacity: Border opacity at the bottom edge (faded point); defaults to 8%.
    ///   - borderWidth: Border line width; defaults to the shared 1px divider width.
    ///   - shadowRadius: Ambient shadow blur radius.
    ///   - shadowY: Ambient shadow vertical offset.
    ///   - material: Base translucent `Material` (light). Defaults to `.ultraThinMaterial`.
    func glassSurface(
        cornerRadius: CGFloat = LiquidGlassMetrics.controlCornerRadius,
        borderColor: Color = .white,
        borderTopOpacity: CGFloat = 0.55,
        borderBottomOpacity: CGFloat = 0.08,
        borderWidth: CGFloat = LiquidGlassMetrics.dividerWidth,
        shadowRadius: CGFloat = 8,
        shadowY: CGFloat = 4,
        material: Material = .ultraThinMaterial
    ) -> some View {
        modifier(
            GlassSurfaceModifier(
                cornerRadius: cornerRadius,
                borderColor: borderColor,
                borderTopOpacity: borderTopOpacity,
                borderBottomOpacity: borderBottomOpacity,
                borderWidth: borderWidth,
                shadowRadius: shadowRadius,
                shadowY: shadowY,
                material: material
            )
        )
    }
}

// MARK: - Dark Glass Surface Modifier

/// Dark "glass-dark" surface treatment for panels shown over opaque
/// backgrounds — settings window, status bar menu, and about window.
///
/// Applies a darker translucent `Material` background composed with a dark
/// tint (so the surface reads dark regardless of the host appearance), a subtle
/// light border, and a slightly stronger outer shadow. Metrics are sourced from
/// `LiquidGlassMetrics` so the surface stays consistent with the shared 8-point
/// spacing grid and macOS HIG control metrics instead of duplicating magic
/// numbers per call site.
///
/// This is the dark counterpart to the light `glassSurface()` style used by
/// controls that float over the video preview.
struct GlassDarkSurfaceModifier: ViewModifier {
    /// Corner radius for panels/cards (20px cards/rails metric).
    var cornerRadius: CGFloat = LiquidGlassMetrics.cardCornerRadius
    /// Base border color (specular gradient is derived from this at top/bottom opacities).
    var borderColor: Color = .white
    /// Border opacity at the top edge (brightest point of the specular gradient).
    var borderTopOpacity: CGFloat = 0.55
    /// Border opacity at the bottom edge (faded point of the specular gradient).
    var borderBottomOpacity: CGFloat = 0.08
    /// Border line width.
    var borderWidth: CGFloat = LiquidGlassMetrics.dividerWidth
    /// Ambient shadow radius.
    var shadowRadius: CGFloat = 12
    /// Ambient shadow vertical offset.
    var shadowY: CGFloat = 4
    /// Base translucent material used behind the panel.
    var material: Material = .regularMaterial
    /// Dark tint composed over the material (as a top-to-bottom gradient rather
    /// than a flat solid fill) so the surface reads dark regardless of the host
    /// appearance while still carrying a hint of depth.
    var darkTint: Color = Color(red: 0.09, green: 0.10, blue: 0.13)
    /// Opacity of the dark tint at the top of the gradient overlay.
    var darkTintTopOpacity: CGFloat = 0.60
    /// Opacity of the dark tint at the bottom of the gradient overlay.
    var darkTintBottomOpacity: CGFloat = 0.45

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Rectangle()
                           .fill(material)
                    LinearGradient(
                        colors: [darkTint.opacity(darkTintTopOpacity), darkTint.opacity(darkTintBottomOpacity)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [borderColor.opacity(borderTopOpacity), borderColor.opacity(borderBottomOpacity)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: borderWidth
                    )
            )
            // Contact shadow: tight, low-radius, close to the surface.
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            // Ambient shadow: soft, wider spread.
            .shadow(color: .black.opacity(0.25), radius: shadowRadius, x: 0, y: shadowY)
    }
}

extension View {
    /// Applies the dark "glass-dark" surface treatment (darker translucent blur,
    /// subtle light border, stronger outer shadow) to a panel rendered over an
    /// opaque background (settings, status bar menu, about window).
    ///
    /// Usage in a settings row:
    /// ```swift
    /// VStack { /* settings row */ }
    ///     .glassDarkSurface()
    /// ```
    ///
    /// - Parameters:
    ///     - cornerRadius: Outer corner radius; defaults to the shared card metric.
    ///     - borderColor: Base border color the specular gradient is derived from; defaults to white.
    ///     - borderTopOpacity: Border opacity at the top edge (brightest point); defaults to 55%.
    ///     - borderBottomOpacity: Border opacity at the bottom edge (faded point); defaults to 8%.
    ///     - borderWidth: Border line width; defaults to the shared 1px divider width.
    ///     - shadowRadius: Ambient shadow blur radius; defaults to a slightly stronger value for panels.
    ///     - shadowY: Ambient shadow vertical offset.
    ///     - material: Base translucent `Material` (dark). Defaults to `.regularMaterial`.
    ///     - darkTint: Color composed over the material to force a dark reading; defaults to a near-black blue.
    ///     - darkTintTopOpacity: Opacity of `darkTint` at the top of its gradient overlay.
    ///     - darkTintBottomOpacity: Opacity of `darkTint` at the bottom of its gradient overlay.
    func glassDarkSurface(
        cornerRadius: CGFloat = LiquidGlassMetrics.cardCornerRadius,
        borderColor: Color = .white,
        borderTopOpacity: CGFloat = 0.55,
        borderBottomOpacity: CGFloat = 0.08,
        borderWidth: CGFloat = LiquidGlassMetrics.dividerWidth,
        shadowRadius: CGFloat = 12,
        shadowY: CGFloat = 4,
        material: Material = .regularMaterial,
        darkTint: Color = Color(red: 0.09, green: 0.10, blue: 0.13),
        darkTintTopOpacity: CGFloat = 0.60,
        darkTintBottomOpacity: CGFloat = 0.45
    ) -> some View {
        modifier(
            GlassDarkSurfaceModifier(
                cornerRadius: cornerRadius,
                borderColor: borderColor,
                borderTopOpacity: borderTopOpacity,
                borderBottomOpacity: borderBottomOpacity,
                borderWidth: borderWidth,
                shadowRadius: shadowRadius,
                shadowY: shadowY,
                material: material,
                darkTint: darkTint,
                darkTintTopOpacity: darkTintTopOpacity,
                darkTintBottomOpacity: darkTintBottomOpacity
            )
        )
    }
}

// MARK: - Liquid Glass Metrics Preview

#Preview("Liquid Glass Metrics") {
    VStack(alignment: .leading, spacing: LiquidGlassMetrics.controlCornerRadius) {
        Text("Liquid Glass Metrics")
            .font(.headline)
        Text("outerMargin: \(LiquidGlassMetrics.outerMargin)")
        Text("pillHeight: \(LiquidGlassMetrics.pillHeight)")
        Text("railWidth: \(LiquidGlassMetrics.railWidth)")
        Text("cardCornerRadius: \(LiquidGlassMetrics.cardCornerRadius)")
        Text("controlCornerRadius: \(LiquidGlassMetrics.controlCornerRadius)")
        Text("divider: \(LiquidGlassMetrics.dividerWidth)px @ \(Int(LiquidGlassMetrics.dividerOpacity * 100))%")
    }
    .font(.caption)
    .foregroundColor(.secondary)
    .frame(width: 280, alignment: .leading)
    .padding()
    .background(Color.gray.opacity(0.2))
    .overlay(
        RoundedRectangle(cornerRadius: LiquidGlassMetrics.controlCornerRadius)
            .stroke(LiquidGlassMetrics.dividerColor, lineWidth: LiquidGlassMetrics.dividerWidth)
    )
    .overlay(
        Circle()
            .fill(LiquidGlassMetrics.accentColor)
            .frame(width: 12, height: 12),
        alignment: .topTrailing
    )
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
