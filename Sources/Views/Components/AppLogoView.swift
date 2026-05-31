import SwiftUI

struct J7LogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Scale coordinate system from original 500x500 SVG canvas to fit custom target rect bounds
        let scaleX = rect.width / 500.0
        let scaleY = rect.height / 500.0
        
        // --- PATH 1 (J Glyph) ---
        path.move(to: CGPoint(x: 190.43 * scaleX, y: 419.92 * scaleY))
        path.addCurve(to: CGPoint(x: 128.91 * scaleX, y: 392.28 * scaleY), control1: CGPoint(x: 166.50 * scaleX, y: 418.26 * scaleY), control2: CGPoint(x: 144.43 * scaleX, y: 408.35 * scaleY))
        path.addCurve(to: CGPoint(x: 117.68 * scaleX, y: 378.17 * scaleY), control1: CGPoint(x: 123.69 * scaleX, y: 386.86 * scaleY), control2: CGPoint(x: 120.76 * scaleX, y: 383.20 * scaleY))
        path.addCurve(to: CGPoint(x: 107.96 * scaleX, y: 322.85 * scaleY), control1: CGPoint(x: 106.89 * scaleX, y: 360.64 * scaleY), control2: CGPoint(x: 103.37 * scaleX, y: 340.52 * scaleY))
        path.addCurve(to: CGPoint(x: 135.74 * scaleX, y: 287.21 * scaleY), control1: CGPoint(x: 111.96 * scaleX, y: 307.66 * scaleY), control2: CGPoint(x: 122.27 * scaleX, y: 294.43 * scaleY))
        path.addCurve(to: CGPoint(x: 159.23 * scaleX, y: 280.91 * scaleY), control1: CGPoint(x: 143.11 * scaleX, y: 283.21 * scaleY), control2: CGPoint(x: 150.24 * scaleX, y: 281.35 * scaleY))
        path.addCurve(to: CGPoint(x: 170.22 * scaleX, y: 282.47 * scaleY), control1: CGPoint(x: 166.46 * scaleX, y: 280.57 * scaleY), control2: CGPoint(x: 168.65 * scaleX, y: 280.91 * scaleY))
        path.addCurve(to: CGPoint(x: 167.88 * scaleX, y: 292.97 * scaleY), control1: CGPoint(x: 172.32 * scaleX, y: 284.57 * scaleY), control2: CGPoint(x: 171.88 * scaleX, y: 286.62 * scaleY))
        path.addCurve(to: CGPoint(x: 159.19 * scaleX, y: 311.04 * scaleY), control1: CGPoint(x: 163.63 * scaleX, y: 299.76 * scaleY), control2: CGPoint(x: 160.60 * scaleX, y: 306.10 * scaleY))
        path.addCurve(to: CGPoint(x: 158.16 * scaleX, y: 329.40 * scaleY), control1: CGPoint(x: 157.87 * scaleX, y: 315.63 * scaleY), control2: CGPoint(x: 157.38 * scaleX, y: 324.66 * scaleY))
        path.addCurve(to: CGPoint(x: 200.93 * scaleX, y: 363.14 * scaleY), control1: CGPoint(x: 161.72 * scaleX, y: 350.54 * scaleY), control2: CGPoint(x: 179.25 * scaleX, y: 364.36 * scaleY))
        path.addCurve(to: CGPoint(x: 216.75 * scaleX, y: 358.94 * scaleY), control1: CGPoint(x: 206.79 * scaleX, y: 362.80 * scaleY), control2: CGPoint(x: 211.62 * scaleX, y: 361.48 * scaleY))
        path.addCurve(to: CGPoint(x: 238.14 * scaleX, y: 330.18 * scaleY), control1: CGPoint(x: 228.13 * scaleX, y: 353.18 * scaleY), control2: CGPoint(x: 235.60 * scaleX, y: 343.17 * scaleY))
        path.addCurve(to: CGPoint(x: 239.26 * scaleX, y: 254.06 * scaleY), control1: CGPoint(x: 238.92 * scaleX, y: 326.32 * scaleY), control2: CGPoint(x: 239.02 * scaleX, y: 319.39 * scaleY))
        path.addLine(to: CGPoint(x: 239.50 * scaleX, y: 182.18 * scaleY))
        path.addLine(to: CGPoint(x: 240.62 * scaleX, y: 181.06 * scaleY))
        path.addLine(to: CGPoint(x: 241.74 * scaleX, y: 179.94 * scaleY))
        path.addLine(to: CGPoint(x: 263.18 * scaleX, y: 179.79 * scaleY))
        path.addCurve(to: CGPoint(x: 285.64 * scaleX, y: 180.18 * scaleY), control1: CGPoint(x: 277.78 * scaleX, y: 179.69 * scaleY), control2: CGPoint(x: 284.96 * scaleX, y: 179.84 * scaleY))
        path.addCurve(to: CGPoint(x: 287.93 * scaleX, y: 263.82 * scaleY), control1: CGPoint(x: 288.28 * scaleX, y: 181.60 * scaleY), control2: CGPoint(x: 288.13 * scaleX, y: 176.91 * scaleY))
        path.addCurve(to: CGPoint(x: 286.71 * scaleX, y: 349.42 * scaleY), control1: CGPoint(x: 287.78 * scaleX, y: 343.46 * scaleY), control2: CGPoint(x: 287.78 * scaleX, y: 344.04 * scaleY))
        path.addCurve(to: CGPoint(x: 261.76 * scaleX, y: 395.61 * scaleY), control1: CGPoint(x: 283.24 * scaleX, y: 367.34 * scaleY), control2: CGPoint(x: 274.65 * scaleX, y: 383.26 * scaleY))
        path.addCurve(to: CGPoint(x: 251.21 * scaleX, y: 404.30 * scaleY), control1: CGPoint(x: 257.02 * scaleX, y: 400.20 * scaleY), control2: CGPoint(x: 251.99 * scaleX, y: 404.30 * scaleY))
        path.addCurve(to: CGPoint(x: 248.82 * scaleX, y: 405.91 * scaleY), control1: CGPoint(x: 251.01 * scaleX, y: 404.30 * scaleY), control2: CGPoint(x: 249.94 * scaleX, y: 405.03 * scaleY))
        path.addCurve(to: CGPoint(x: 244.86 * scaleX, y: 408.40 * scaleY), control1: CGPoint(x: 247.70 * scaleX, y: 406.74 * scaleY), control2: CGPoint(x: 245.94 * scaleX, y: 407.86 * scaleY))
        path.addCurve(to: CGPoint(x: 242.17 * scaleX, y: 409.72 * scaleY), control1: CGPoint(x: 243.79 * scaleX, y: 408.89 * scaleY), control2: CGPoint(x: 242.57 * scaleX, y: 409.47 * scaleY))
        path.addCurve(to: CGPoint(x: 240.71 * scaleX, y: 410.45 * scaleY), control1: CGPoint(x: 241.78 * scaleX, y: 409.96 * scaleY), control2: CGPoint(x: 241.10 * scaleX, y: 410.31 * scaleY))
        path.addCurve(to: CGPoint(x: 237.10 * scaleX, y: 411.96 * scaleY), control1: CGPoint(x: 240.32 * scaleX, y: 410.60 * scaleY), control2: CGPoint(x: 238.66 * scaleX, y: 411.28 * scaleY))
        path.addCurve(to: CGPoint(x: 219.47 * scaleX, y: 417.97 * scaleY), control1: CGPoint(x: 230.85 * scaleX, y: 414.65 * scaleY), control2: CGPoint(x: 222.26 * scaleX, y: 417.58 * scaleY))
        path.addCurve(to: CGPoint(x: 200.92 * scaleX, y: 420.07 * scaleY), control1: CGPoint(x: 208.34 * scaleX, y: 419.58 * scaleY), control2: CGPoint(x: 205.70 * scaleX, y: 419.87 * scaleY))
        path.addCurve(to: CGPoint(x: 190.42 * scaleX, y: 419.92 * scaleY), control1: CGPoint(x: 197.99 * scaleX, y: 420.17 * scaleY), control2: CGPoint(x: 193.25 * scaleX, y: 420.12 * scaleY))
        path.closeSubpath()
        
        // --- PATH 2 (7 Glyph) ---
        path.move(to: CGPoint(x: 304.3 * scaleX, y: 302.15 * scaleY))
        path.addCurve(to: CGPoint(x: 303.71 * scaleX, y: 255.52 * scaleY), control1: CGPoint(x: 304.3 * scaleX, y: 301.71 * scaleY), control2: CGPoint(x: 303.71 * scaleX, y: 290.68 * scaleY))
        path.addCurve(to: CGPoint(x: 304.74 * scaleX, y: 207.38 * scaleY), control1: CGPoint(x: 303.71 * scaleX, y: 209.57 * scaleY), control2: CGPoint(x: 303.71 * scaleX, y: 209.43 * scaleY))
        path.addCurve(to: CGPoint(x: 309.92 * scaleX, y: 197.76 * scaleY), control1: CGPoint(x: 305.33 * scaleX, y: 206.26 * scaleY), control2: CGPoint(x: 307.67 * scaleX, y: 191.91 * scaleY))
        path.addCurve(to: CGPoint(x: 318.37 * scaleX, y: 182.38 * scaleY), control1: CGPoint(x: 312.21 * scaleX, y: 193.61 * scaleY), control2: CGPoint(x: 316.02 * scaleX, y: 186.68 * scaleY))
        path.addCurve(to: CGPoint(x: 329.01 * scaleX, y: 163.00 * scaleY), control1: CGPoint(x: 320.76 * scaleX, y: 178.08 * scaleY), control2: CGPoint(x: 325.55 * scaleX, y: 169.34 * scaleY))
        path.addCurve(to: CGPoint(x: 335.55 * scaleX, y: 150.55 * scaleY), control1: CGPoint(x: 332.53 * scaleX, y: 156.65 * scaleY), control2: CGPoint(x: 335.46 * scaleX, y: 151.04 * scaleY))
        path.addCurve(to: CGPoint(x: 257.72 * scaleX, y: 149.43 * scaleY), control1: CGPoint(x: 335.70 * scaleX, y: 149.72 * scaleY), control2: CGPoint(x: 332.96 * scaleX, y: 149.67 * scaleY))
        path.addLine(to: CGPoint(x: 179.79 * scaleX, y: 149.19 * scaleY))
        path.addLine(to: CGPoint(x: 178.52 * scaleX, y: 148.02 * scaleY))
        path.addCurve(to: CGPoint(x: 177.15 * scaleX, y: 142.80 * scaleY), control1: CGPoint(x: 177.10 * scaleX, y: 146.70 * scaleY), control2: CGPoint(x: 176.42 * scaleX, y: 144.11 * scaleY))
        path.addCurve(to: CGPoint(x: 186.38 * scaleX, y: 129.62 * scaleY), control1: CGPoint(x: 177.44 * scaleX, y: 142.26 * scaleY), control2: CGPoint(x: 181.54 * scaleX, y: 136.35 * scaleY))
        path.addCurve(to: CGPoint(x: 198.73 * scaleX, y: 112.19 * scaleY), control1: CGPoint(x: 191.17 * scaleX, y: 122.88 * scaleY), control2: CGPoint(x: 196.73 * scaleX, y: 115.02 * scaleY))
        path.addCurve(to: CGPoint(x: 213.13 * scaleX, y: 93.59 * scaleY), control1: CGPoint(x: 209.91 * scaleX, y: 96.22 * scaleY), control2: CGPoint(x: 211.18 * scaleX, y: 94.61 * scaleY))
        path.addCurve(to: CGPoint(x: 309.57 * scaleX, y: 92.42 * scaleY), control1: CGPoint(x: 215.03 * scaleX, y: 92.61 * scaleY), control2: CGPoint(x: 215.62 * scaleX, y: 92.61 * scaleY))
        path.addCurve(to: CGPoint(x: 406.05 * scaleX, y: 92.76 * scaleY), control1: CGPoint(x: 377.93 * scaleX, y: 92.27 * scaleY), control2: CGPoint(x: 404.59 * scaleX, y: 92.37 * scaleY))
        path.addCurve(to: CGPoint(x: 413.57 * scaleX, y: 105.11 * scaleY), control1: CGPoint(x: 411.86 * scaleX, y: 94.32 * scaleY), control2: CGPoint(x: 415.03 * scaleX, y: 99.55 * scaleY))
        path.addCurve(to: CGPoint(x: 406.49 * scaleX, y: 118.93 * scaleY), control1: CGPoint(x: 413.23 * scaleX, y: 106.23 * scaleY), control2: CGPoint(x: 410.05 * scaleX, y: 112.43 * scaleY))
        path.addCurve(to: CGPoint(x: 343.01 * scaleX, y: 235.39 * scaleY), control1: CGPoint(x: 400.24 * scaleX, y: 130.31 * scaleY), control2: CGPoint(x: 356.64 * scaleX, y: 210.19 * scaleY))
        path.addCurve(to: CGPoint(x: 326.41 * scaleX, y: 265.91 * scaleY), control1: CGPoint(x: 339.30 * scaleX, y: 242.23 * scaleY), control2: CGPoint(x: 326.41 * scaleX, y: 256.00 * scaleY))
        path.addCurve(to: CGPoint(x: 312.01 * scaleX, y: 292.52 * scaleY), control1: CGPoint(x: 320.99 * scaleX, y: 275.87 * scaleY), control2: CGPoint(x: 314.50 * scaleX, y: 287.83 * scaleY))
        path.addCurve(to: CGPoint(x: 304.30 * scaleX, y: 302.19 * scaleY), control1: CGPoint(x: 306.39 * scaleX, y: 303.07 * scaleY), control2: CGPoint(x: 305.86 * scaleX, y: 303.75 * scaleY))
        path.closeSubpath()
        
        return path
    }
}

struct AppLogoView: View {
    // Kept for backward compatibility, though the brand asset is multi-color
    var color: Color = Color(hex: "#0340c7")
    
    var body: some View {
        Image("AppLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}
