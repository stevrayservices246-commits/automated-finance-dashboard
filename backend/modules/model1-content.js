module.exports = {
  name: "stub",
  status: "ready",
  async runDailyAutomations(){ return { success:true, revenue:0 }; },
  async getStats(){ return { success:true }; }
};
