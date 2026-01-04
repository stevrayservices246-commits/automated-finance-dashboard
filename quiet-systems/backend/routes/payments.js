const express = require("express");
const router = express.Router();
const payments = require("../modules/payment-processor");

router.post("/paypal", async (req,res)=>res.json(await payments.processPayPalPayment(req.body)));
router.post("/google-pay", async (req,res)=>res.json(await payments.processGooglePay(req.body)));
router.post("/webhook/paypal", async (req,res)=>res.json(await payments.handlePayPalWebhook(req.body)));

module.exports = router;
