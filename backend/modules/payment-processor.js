const axios = require("axios");
const crypto = require("crypto");

class PaymentProcessor {
  constructor() {
    this.name = "Payment Processor";
    this.status = "ready";
    // Patch script will rewrite this to PayPal + Google Pay only.
    this.supportedMethods = ['paypal', 'google_pay'];
  }

  async processPayPalPayment(paymentData) {
    const { amount, currency = "USD", description = "Digital Product", returnUrl, cancelUrl } = paymentData;

    // Minimal PayPal order creation (works once env vars are set)
    try {
      const auth = Buffer.from(`${process.env.PAYPAL_CLIENT_ID}:${process.env.PAYPAL_SECRET}`).toString("base64");
      const tokenRes = await axios.post(
        process.env.PAYPAL_ENV === "live"
          ? "https://api-m.paypal.com/v1/oauth2/token"
          : "https://api-m.sandbox.paypal.com/v1/oauth2/token",
        "grant_type=client_credentials",
        { headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/x-www-form-urlencoded" } }
      );

      const accessToken = tokenRes.data.access_token;

      const orderRes = await axios.post(
        process.env.PAYPAL_ENV === "live"
          ? "https://api-m.paypal.com/v2/checkout/orders"
          : "https://api-m.sandbox.paypal.com/v2/checkout/orders",
        {
          intent: "CAPTURE",
          purchase_units: [{ amount: { currency_code: currency, value: String(amount) }, description }],
          application_context: {
            return_url: returnUrl || "https://example.com/success",
            cancel_url: cancelUrl || "https://example.com/cancel"
          }
        },
        { headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" } }
      );

      return { success: true, provider: "paypal", orderId: orderRes.data.id, status: orderRes.data.status, links: orderRes.data.links };
    } catch (e) {
      return { success: false, provider: "paypal", error: e.response?.data || e.message };
    }
  }

  async processGooglePay(paymentData) {
    // Placeholder: real Google Pay requires merchant integration in frontend + processor
    return {
      success: true,
      provider: "google_pay",
      transactionId: "GP_" + Date.now() + "_" + crypto.randomBytes(4).toString("hex"),
      amount: paymentData.amount || 0,
      currency: paymentData.currency || "USD"
    };
  }

  async handlePayPalWebhook(body) {
    return { success: true, received: true };
  }

  async processDailySettlement() {
    return { success: true, date: new Date().toISOString().slice(0,10), amount: 0 };
  }

  async healthCheck() {
    return { status: "healthy", timestamp: new Date().toISOString() };
  }
}

module.exports = new PaymentProcessor();
