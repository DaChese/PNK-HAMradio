const express = require("express");
const { exec } = require("child_process");
const cors = require("cors");

const app = express();
app.use(cors());

app.get("/logs/:service", (req, res) => {
  const service = req.params.service;
  exec(`docker logs --tail 50 --timestamps ${service}`, (err, stdout, stderr) => {
    if (err) {
      return res.status(500).send(stderr || err.message);
    }
    res.type("text/plain").send(stdout);
  });
});

const PORT = 6061;
app.listen(PORT, () => console.log(`📜 Log server running on port ${PORT}`));
