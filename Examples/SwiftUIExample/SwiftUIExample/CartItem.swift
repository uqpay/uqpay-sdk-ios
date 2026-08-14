//
//  CartItem.swift
//  SwiftUIExample
//
//  Created by UQPAY
//

import Foundation
import Combine

struct CartItem: Identifiable {
    let id = UUID()
    let name: String
    let size: String
    let price: Double
    let imageName: String // System image name for demo
}

class CartViewModel: ObservableObject {
    @Published var cartItems: [CartItem] = [
        CartItem(name: "T-Shirt", size: "XL", price: 10.00, imageName: "tshirt"),
        CartItem(name: "Jeans", size: "XL", price: 10.00, imageName: "rectangle.stack"),
        // WeChat Pay QRs from the sandbox charge REAL money, so real-device
        // testing needs a one-cent order: remove the other items and this is
        // the whole charge.
        CartItem(name: "Test Payment", size: "1 cent · for real-money wallet tests", price: 0.01, imageName: "centsign.circle")
    ]

    let discount: Double = 0.00

    /// Waived for micro totals so a one-cent wallet test charges exactly 0.01.
    var deliveryFee: Double {
        subtotal < 1.00 ? 0.00 : 2.00
    }

    var subtotal: Double {
        cartItems.reduce(0) { $0 + $1.price }
    }

    var total: Double {
        subtotal + deliveryFee - discount
    }

    let shippingAddress = ShippingAddress(
        name: "John",
        phoneCode: "+65",
        phoneNumber: "520*102",
        address: "123 Orchard Road, Singapore 238888"
    )

    func removeItem(_ item: CartItem) {
        cartItems.removeAll { $0.id == item.id }
    }
}

struct ShippingAddress {
    let name: String
    let phoneCode: String
    let phoneNumber: String
    let address: String

    var formattedPhone: String {
        "\(phoneCode) \(phoneNumber)"
    }
}