// Doudizhu Arc Edition - Backend Server
// 1. Static file server (index.html)
// 2. Nanopayments game pass endpoint (x402)

import express from "express";
import crypto from "crypto";
import "dotenv/config";

const app = express();
const PORT = process.env.PORT || 3000;
const SELLER_ADDRESS = process.env.SELLER_ADDRESS;
const PASS_SECRET = process.env.PASS_SECRET || "dev-default-secret-change-me";

// Static files
app.use(express.static(".", { index: "index.html" }));

// Nanopayments middleware (dynamic import, auto-skip if package not installed)
let gateway;
if (SELLER_ADDRESS) {
  try {
    const { createGatewayMiddleware } = await import("@circle-fin/x402-batching/server");
    gateway = createGatewayMiddleware({
      sellerAddress: SELLER_ADDRESS,
      networks: ["eip155:5042002"], // Arc Testnet
    });
    console.log("Nanopayments middleware enabled");
  } catch (err) {
    console.warn("Nanopayments not enabled:", err.code === "ERR_MODULE_NOT_FOUND" ? "package not installed" : err.message);
  }
}

// Game pass endpoint - $0.01 via x402
app.get(
  "/api/game-pass",
  ...(gateway ? [gateway.require("$0.01")] : []),
  (req, res) => {
    const token = crypto.randomBytes(32).toString("hex");
    const expiresAt = Date.now() + 24 * 60 * 60 * 1000;
    const signature = crypto
      .createHmac("sha256", PASS_SECRET)
      .update(token + expiresAt)
      .digest("hex");

    res.json({
      pass: token,
      expiresAt,
      signature,
      payer: req.payment?.payer || "free-mode",
    });
  }
);

// Verify game pass
app.get("/api/verify-pass", (req, res) => {
  const { pass, expiresAt, signature } = req.query;
  if (!pass || !expiresAt || !signature) {
    return res.json({ valid: false });
  }
  if (Date.now() > Number(expiresAt)) {
    return res.json({ valid: false, reason: "expired" });
  }
  const expected = crypto
    .createHmac("sha256", PASS_SECRET)
    .update(pass + expiresAt)
    .digest("hex");
  res.json({ valid: signature === expected });
});

app.listen(PORT, () => {
  console.log(`\nDoudizhu Arc Edition started!`);
  console.log(`Open browser: http://localhost:${PORT}`);
  console.log(`\nFeature status:`);
  console.log(`  Static file server: enabled`);
  console.log(`  Nanopayments: ${gateway ? "enabled ($0.01/pass)" : "free mode"}`);
});
