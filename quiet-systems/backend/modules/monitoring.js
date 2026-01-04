class Monitoring {
  constructor() {
    this.name = "Monitoring";
    this.status = "ready";
    this.alerts = [];
  }

  async getDashboardData() {
    const sheets = require("./sheets-integration");
    const revenue = await sheets.getMTDRevenue();
    return {
      metrics: {
        revenue: { current: revenue.amount || 0, target: 100000 }
      },
      checks: { apis: { status: "healthy" } }
    };
  }
}
module.exports = new Monitoring();
