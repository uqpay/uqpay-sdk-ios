import UIKit
import CoreImage

enum QRCodeGenerator {
    static func generateQRImage(from payload: String) -> UIImage? {
        guard let data = payload.data(using: .utf8) else { return nil }

        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue("H", forKey: "inputCorrectionLevel")

        guard let ciImage = filter?.outputImage else { return nil }

        let transform = CGAffineTransform(scaleX: 4, y: 4)
        let scaled = ciImage.transformed(by: transform)

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
