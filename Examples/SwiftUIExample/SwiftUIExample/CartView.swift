//
//  CartView.swift
//  SwiftUIExample
//
//  Created by UQPAY
//

import SwiftUI
import UqpayCore
import UqpayPayments

struct CartView: View {
    @StateObject private var cartViewModel = CartViewModel()
    @ObservedObject var contentViewModel: ContentViewModel
    @Binding var isShowingPaymentListV2: Bool
    @Environment(\.dismiss) var dismiss
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    init(isShowingPaymentListV2: Binding<Bool>, contentViewModel: ContentViewModel) {
        self._isShowingPaymentListV2 = isShowingPaymentListV2
        self.contentViewModel = contentViewModel
    }

    var body: some View {
        
            VStack(spacing: 0) {
                // Cart Items List
                ScrollView {
                    VStack(spacing: 0) {
                        // Items header
                        HStack {
                            Text("Item")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                        // Cart items
                        ForEach(cartViewModel.cartItems) { item in
                            CartItemView(item: item, onRemove: {
                                cartViewModel.removeItem(item)
                            })
                            Divider()
                                .padding(.horizontal, 16)
                        }

                        // Price breakdown
                        VStack(spacing: 12) {
                            // Subtotal
                            HStack {
                                Text("Subtotal")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("S$\(String(format: "%.2f", cartViewModel.subtotal))")
                                    .font(.system(size: 14, weight: .medium))
                            }

                            // Delivery Fee
                            HStack {
                                Text("Delivery Fee")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("S$\(String(format: "%.2f", cartViewModel.deliveryFee))")
                                    .font(.system(size: 14, weight: .medium))
                            }

                            // Discount
                            HStack {
                                Text("Discount")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(String(format: "%.2f", cartViewModel.discount))")
                                    .font(.system(size: 14, weight: .medium))
                            }

                            Divider()

                            // Total
                            HStack {
                                Text("Total")
                                    .font(.system(size: 16, weight: .semibold))
                                Spacer()
                                Text("S$\(String(format: "%.2f", cartViewModel.total))")
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)

                        // Shipping Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Shipping")
                                .font(.system(size: 16, weight: .semibold))

                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 20))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(cartViewModel.shippingAddress.name) | \(cartViewModel.shippingAddress.formattedPhone)")
                                        .font(.system(size: 14, weight: .medium))
                                    Text(cartViewModel.shippingAddress.address)
                                        .font(.system(size: 13))
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(8)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                    }
                }

                // Checkout Button
                Button {
                    Task {
                        await handleCheckout()
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue.opacity(0.6))
                            .cornerRadius(8)
                    } else {
                        Text("Checkout")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                }
                .disabled(isLoading)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: -2)
            }
            .navigationTitle("My Cart")
            .navigationBarTitleDisplayMode(.inline)
            
        
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    /// Charges exactly what the cart shows.
    ///
    /// The amount comes from the cart total rather than a constant, so what the
    /// customer sees and what the intent is created for cannot drift apart.
    private func handleCheckout() async {
        isLoading = true

        await contentViewModel.prepareCheckout(
            amount: Self.decimal(from: cartViewModel.total),
            description: "Order of \(cartViewModel.cartItems.count) item(s)"
        )

        isLoading = false

        if contentViewModel.state.intent != nil {
            isShowingPaymentListV2 = true
            dismiss()
        } else if let message = contentViewModel.state.errorMessage {
            errorMessage = message
            showError = true
        }
    }

    /// Converts through a fixed-scale string so binary floating point cannot
    /// introduce a rounding difference between the display and the charge.
    private static func decimal(from value: Double) -> Decimal {
        Decimal(string: String(format: "%.2f", value)) ?? 0
    }
}

struct CartItemView: View {
    let item: CartItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Product Image
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 60, height: 60)

                Image(systemName: item.imageName)
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
            }

            // Product Details
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 14, weight: .medium))
                Text(item.size)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }

            Spacer()

            // Price and Remove
            VStack(alignment: .trailing, spacing: 8) {
                Text("S$\(String(format: "%.2f", item.price))")
                    .font(.system(size: 14, weight: .semibold))

                Button {
                    onRemove()
                } label: {
                    Text("Remove")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    CartView(isShowingPaymentListV2: .constant(false), contentViewModel: ContentViewModel())
}
