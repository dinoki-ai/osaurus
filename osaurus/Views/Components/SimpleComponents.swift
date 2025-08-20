//
//  SimpleComponents.swift
//  osaurus
//
//  Minimalistic UI components with clean edges and outline styling
//

import SwiftUI
import AppKit

// MARK: - Minimalistic Card Background
struct MinimalCard: View {
    @Environment(\.theme) private var theme
    var cornerRadius: CGFloat = 12
    var borderWidth: CGFloat = 1
    var isHovering: Bool = false
    var isPressed: Bool = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(theme.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isPressed ? theme.focusBorder : 
                        isHovering ? theme.primaryBorder : theme.cardBorder,
                        lineWidth: borderWidth
                    )
            )
            .shadow(
                color: theme.shadowColor.opacity(theme.shadowOpacity),
                radius: isHovering ? 12 : 8,
                x: 0,
                y: isHovering ? 4 : 2
            )
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
}

// MARK: - Simple Card
struct SimpleCard<Content: View>: View {
    @Environment(\.theme) private var theme
    let content: Content
    let padding: CGFloat
    @State private var isHovering = false
    @State private var isPressed = false
    
    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(MinimalCard(isHovering: isHovering, isPressed: isPressed))
            .onHover { hovering in
                isHovering = hovering
            }
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
    }
}

// MARK: - Minimal Outline Button (formerly GradientButton)
struct GradientButton: View {
    @Environment(\.theme) private var theme
    let title: String
    let icon: String?
    let action: () -> Void
    var isDestructive: Bool = false
    var isPrimary: Bool = true
    
    @State private var isPressed = false
    @State private var isHovering = false
    
    var buttonColor: Color {
        if isDestructive {
            return theme.errorColor
        }
        return theme.accentColor
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(isPrimary ? .white : buttonColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Group {
                    if isPrimary {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(buttonColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(buttonColor, lineWidth: 1.5)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.buttonBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        isPressed ? buttonColor : 
                                        isHovering ? buttonColor.opacity(0.8) : theme.buttonBorder,
                                        lineWidth: 1.5
                                    )
                            )
                    }
                }
            )
            .shadow(
                color: theme.shadowColor.opacity(isHovering ? theme.shadowOpacity * 2 : theme.shadowOpacity),
                radius: isHovering ? 6 : 4,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Simple Toggle Button
struct SimpleToggleButton: View {
    @Environment(\.theme) private var theme
    let isOn: Bool
    let title: String
    let icon: String
    let action: () -> Void
    
    @State private var isHovering = false
    @State private var isPressed = false
    
    var buttonColor: Color {
        isOn ? theme.errorColor : theme.successColor
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .rotationEffect(.degrees(isHovering ? 8 : 0))
                    .scaleEffect(isHovering ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(buttonColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.buttonBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isPressed ? buttonColor : (isHovering ? buttonColor.opacity(0.95) : buttonColor.opacity(0.75)),
                                lineWidth: 1.8
                            )
                    )
            )
            .shadow(
                color: theme.shadowColor.opacity(isHovering ? theme.shadowOpacity * 2 : theme.shadowOpacity),
                radius: isHovering ? 6 : 4,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Copy URL Field
struct CopyableURLField: View {
    @Environment(\.theme) private var theme
    let label: String
    let url: String
    @State private var showCopied = false
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.secondaryText)
            
            HStack(spacing: 12) {
                Text(url)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.inputBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.inputBorder, lineWidth: 1)
                            )
                    )
                
                Button(action: copyURL) {
                    ZStack {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(showCopied ? theme.successColor : theme.primaryText)
                    }
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(theme.buttonBackground)
                            .overlay(
                                Circle()
                                    .stroke(
                                        isHovering ? theme.focusBorder : theme.buttonBorder,
                                        lineWidth: 1
                                    )
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .help(showCopied ? "Copied!" : "Copy to clipboard")
                .onHover { hovering in
                    isHovering = hovering
                }
            }
        }
    }
    
    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopied = false
            }
        }
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    @Environment(\.theme) private var theme
    let status: String
    let color: Color
    let isAnimating: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.3), lineWidth: 3)
                        .scaleEffect(isAnimating ? 2.0 : 1.0)
                        .opacity(isAnimating ? 0 : 1)
                        .animation(
                            isAnimating ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .default,
                            value: isAnimating
                        )
                )
            
            Text(status)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(theme.cardBackground)
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Simple Progress Bar
struct SimpleProgressBar: View {
    @Environment(\.theme) private var theme
    let progress: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(theme.cardBorder, lineWidth: 1)
                    )
                    .frame(height: 8)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.accentColor)
                    .frame(width: max(0, geometry.size.width * progress - 2), height: 6)
                    .offset(x: 1)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Icon Badge
struct IconBadge: View {
    @Environment(\.theme) private var theme
    let icon: String
    let color: Color
    var size: CGFloat = 50
    
    var body: some View {
        ZStack {
            Circle()
                .fill(theme.cardBackground)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.3), lineWidth: 1.5)
                )
            
            Image(systemName: icon)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundColor(color)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Theme Toggle (removed)
