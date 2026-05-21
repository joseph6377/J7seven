import SwiftUI

struct CoverImageView: View {
    @Environment(AppState.self) private var appState
    let id: UUID
    @State private var coverData: Data?
    @State private var bookTitle: String = ""

    // Deterministic gradient per book based on title hash
    private var placeholderGradient: LinearGradient {
        let stringToHash = bookTitle.isEmpty ? id.uuidString : bookTitle
        let hash = abs(stringToHash.hashValue)
        
        // Generate a base hue between 0.0 and 1.0 (360 degrees)
        let baseHue = Double(hash % 360) / 360.0
        
        // Monochromatic/analogous theme colors
        let color1 = Color(hue: baseHue, saturation: 0.60, brightness: 0.45)
        
        // Analogous: shift hue slightly (+25 degrees = ~0.07 of 1.0) and adjust brightness
        let shiftedHue = (baseHue + 0.07).truncatingRemainder(dividingBy: 1.0)
        let color2 = Color(hue: shiftedHue, saturation: 0.65, brightness: 0.28)
        
        // Shifting coordinates based on title hashes for maximum visual premium variety
        let coordinates: [(UnitPoint, UnitPoint)] = [
            (.topLeading, .bottomTrailing),
            (.topTrailing, .bottomLeading),
            (.leading, .trailing),
            (.top, .bottom),
            (.bottomLeading, .topTrailing),
            (.bottomTrailing, .topLeading)
        ]
        let (start, end) = coordinates[hash % coordinates.count]
        
        return LinearGradient(colors: [color1, color2], startPoint: start, endPoint: end)
    }

    var body: some View {
        Group {
            if let data = coverData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderGradient
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "book.closed")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.white.opacity(0.4))
                            
                            if !bookTitle.isEmpty {
                                Text(bookTitle.prefix(2).uppercased())
                                    .font(.system(size: 14, weight: .bold, design: .serif))
                                    .foregroundStyle(.white.opacity(0.65))
                                    .tracking(2)
                            }
                        }
                    )
            }
        }
        .task {
            if let doc = appState.libraryService.loadDocument(id: id) {
                coverData = doc.coverImageData
                bookTitle = doc.title
            }
        }
    }
}

// UIImage Extension to extract the dominant/average color of the book cover
extension UIImage {
    var dominantColor: UIColor? {
        guard let cgImage = self.cgImage else { return nil }
        
        let width = 1
        let height = 1
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        var pixelData = [UInt8](repeating: 0, count: 4)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let r = CGFloat(pixelData[0]) / 255.0
        let g = CGFloat(pixelData[1]) / 255.0
        let b = CGFloat(pixelData[2]) / 255.0
        let a = CGFloat(pixelData[3]) / 255.0
        
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}
