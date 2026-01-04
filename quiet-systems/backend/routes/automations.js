const express = require("express");
const router = express.Router();

router.post("/run", async (req,res)=>res.json({ successCount: 1, totalTasks: 1 }));
router.post("/simulate-month", async (req,res)=>res.json({ totalRevenue: 0 }));

module.exports = router;
