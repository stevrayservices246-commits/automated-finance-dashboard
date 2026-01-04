const express = require("express");
const router = express.Router();
const sheets = require("../modules/sheets-integration");
router.get("/mtd", async (req,res)=>res.json(await sheets.getMTDRevenue()));
module.exports = router;
