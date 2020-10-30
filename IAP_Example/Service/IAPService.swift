//
//  IAPService.swift
//  IAP_Example
//
//  Created by hjliu on 2020/10/26.
//

import StoreKit

protocol Product {
  typealias ProductIdentifier = String
  typealias ProductsRequestCompletionHandler = (Bool, [SKProduct]?) -> ()
}

class IAPService: NSObject, Product {
  
  private let productIdentifiers: Set<ProductIdentifier>
  private var purchasedProductIdentifiers: Set<ProductIdentifier> = [] // 已購買商品ID
  
  private var productsRequest: SKProductsRequest?
  private var productsRequestCompletionHandler: ProductsRequestCompletionHandler?
  
  init(productIds: Set<ProductIdentifier>) {
    
    self.productIdentifiers = productIds
    
    for productIdentifier in productIds {
      let purchased = UserDefaults.standard.bool(forKey: productIdentifier)
      if purchased {
        purchasedProductIdentifiers.insert(productIdentifier)
        print("Previously purchased: \(productIdentifier)")
      } else {
        print("Not purchased: \(productIdentifier)")
      }
    }
    
    super.init()
    SKPaymentQueue.default().add(self) // 監聽 購買交易
  }
  
  deinit {
    SKPaymentQueue.default().remove(self) // 取消監聽 購買交易
  }
  
  // 查詢商品
  func requestProducts(completionHandler: @escaping ProductsRequestCompletionHandler) {
    productsRequest?.cancel()
    productsRequestCompletionHandler = completionHandler
    
    productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers)
    productsRequest!.delegate = self
    productsRequest!.start()
  }
  
  // 購買
  func buyProduct(_ product: SKProduct) {
    print("購買 \(product.productIdentifier)")
    let payment = SKPayment(product: product)
    SKPaymentQueue.default().add(payment)
  }
  
  // 恢復
  func restorePurchases() {
    SKPaymentQueue.default().restoreCompletedTransactions()
  }
  
  // 是否允許IAP
  func canMakePayments() -> Bool {
    return SKPaymentQueue.canMakePayments()
  }
}

extension IAPService: SKProductsRequestDelegate {
  
  // 收到商品信息
  func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
    print("商品信息Request 成功")
    
    let products = response.products
    productsRequestCompletionHandler?(true, products)
    clearRequestAndHandler()
    
    for p in products {
      print("商品: \(p.productIdentifier) \(p.localizedTitle) \(p.localizedDescription) \(p.regularPrice ?? p.price.stringValue)")
    }
    
    // 失敗的ids
    let invalidProductIdentifiers = response.invalidProductIdentifiers
    print(invalidProductIdentifiers)
  }
  
  func request(_ request: SKRequest, didFailWithError error: Error) {
    print("商品信息Request 失敗:\(error.localizedDescription)")
    
    productsRequestCompletionHandler?(false, nil)
    clearRequestAndHandler()
  }
  
  func requestDidFinish(_ request: SKRequest) {
    print("商品信息Request 結束")
  }
  
  private func clearRequestAndHandler() {
    productsRequest = nil
    productsRequestCompletionHandler = nil
  }
}

extension IAPService: SKPaymentTransactionObserver {
  
  // 監聽購買結果
  func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
    
    for transaction in transactions {
      
      switch transaction.transactionState {
      case .purchased:
        // 購買成功，此時要提供給用戶相應的內容
        complete(transaction: transaction)
        break
      case .failed:
        // 購買錯誤，此時要根據錯誤的代碼給用戶相應的提示
        fail(transaction: transaction)
        break
      case .restored:
        // 恢復已購產品，此時需要將已經購買的商品恢復給用戶
        restore(transaction: transaction)
        break
      case .deferred:
        break
      case .purchasing:
        // 購買中，此時可更新UI來展現購買的過程
        print("商品購買中")
        break
      @unknown default: break
      }
    }
  }
  
  // 錯誤
  func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
    print("paymentQueue Error:\(error.localizedDescription)")
  }
  
  
  // 商品交易完成
  private func complete(transaction: SKPaymentTransaction) {
    print("商品交易complete...")
    deliverPurchaseNotificationFor(identifier: transaction.payment.productIdentifier)
    SKPaymentQueue.default().finishTransaction(transaction)
    validateReceipt()
  }
  
  //驗證憑據，獲取到蘋果返回的交易憑據
  private func validateReceipt() {
    
    // It’s a special string key, which a developer uses to validate receipts with auto-renewable subscriptions.
    // You will put Shared Secret into HTTPS request parameters.
    //
    // Go to App Store Connect, open your app,
    // then go to “Functions” and in “In-App Purchases” tab you will see “App-Specific Shared Secret” button.
    // Generate a new key, if it doesn’t exist.
    let sharedSecret = "YOUR_SHARED_SECRET"
    
    #if DEBUG
    let verifyReceiptUrlString = "https://sandbox.itunes.apple.com/verifyReceipt"
    #else
    let verifyReceiptUrlString = "https://buy.itunes.apple.com/verifyReceipt"
    #endif
    
    guard
      let receiptURL = Bundle.main.appStoreReceiptURL,
      let receiptString = try? Data(contentsOf: receiptURL).base64EncodedString(),
      let verifyReceiptUrl = URL(string: verifyReceiptUrlString)
    else { return }
    
    let requestData : [String : Any] = ["receipt-data" : receiptString,
                                        "password" : sharedSecret,
                                        "exclude-old-transactions" : false]
    let httpBody = try? JSONSerialization.data(withJSONObject: requestData, options: [])
    
    var request = URLRequest(url: verifyReceiptUrl)
    request.httpMethod = "POST"
    request.setValue("Application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = httpBody
    URLSession.shared.dataTask(with: request)  { (data, response, error) in
      
      DispatchQueue.main.async {
        if let data = data, let str = try? JSONSerialization.jsonObject(with: data, options:.allowFragments) as? String {
          print(str)
        }
      }
      
    }.resume()
  }
  
  // 已購買過商品
  private func restore(transaction: SKPaymentTransaction) {
    guard let productIdentifier = transaction.original?.payment.productIdentifier else { return }
    print("商品交易restore... \(productIdentifier)")
    deliverPurchaseNotificationFor(identifier: productIdentifier)
    SKPaymentQueue.default().finishTransaction(transaction)
  }
  
  // 商品交易失敗
  private func fail(transaction: SKPaymentTransaction) {
    print("商品交易fail...")
    if let transactionError = transaction.error as? SKError, let localizedDescription = transaction.error?.localizedDescription, transactionError.code != .paymentCancelled {
      print("Transaction Error: \(localizedDescription)")
    }
    
    SKPaymentQueue.default().finishTransaction(transaction)
  }
  
  private func deliverPurchaseNotificationFor(identifier: String?) {
    guard let identifier = identifier else { return }
    purchasedProductIdentifiers.insert(identifier)
    UserDefaults.standard.set(true, forKey: identifier)
    NotificationCenter.default.post(name: .IAPHelperPurchaseNotification, object: identifier)
  }
}



extension SKProduct {
  
  // 轉換成該所在地金額
  var regularPrice: String? {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = self.priceLocale
    return formatter.string(from: self.price)
  }
}


extension NSNotification.Name {
  static let IAPHelperPurchaseNotification = NSNotification.Name("IAPHelperPurchaseNotification")
}
