const { google } = require("googleapis");
const path = require("path");

class SheetsIntegration {
  constructor() {
    this.name = "Sheets Integration";
    this.status = "ready";
    this.spreadsheetId = process.env.GOOGLE_SHEETS_ID || "";
    this.sheets = null;
    this.init();
  }

  async init() {
    try {
      const auth = new google.auth.GoogleAuth({
        keyFile: path.join(__dirname, "../config/service-account.json"),
        scopes: ["https://www.googleapis.com/auth/spreadsheets"]
      });
      this.sheets = google.sheets({ version: "v4", auth });
      this.status = "ready";
    } catch (e) {
      this.status = "degraded";
    }
  }

  async getMTDRevenue() {
    // Minimal stub until you wire real sheet ranges
    return { success: true, amount: 0 };
  }

  async healthCheck() {
    return { status: this.status === "ready" ? "healthy" : "degraded", timestamp: new Date().toISOString() };
  }
}

module.exports = new SheetsIntegration();
