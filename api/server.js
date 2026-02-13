const express = require('express');
const app = express();
const PORT = 3000;

app.get('/api/health', (req, res) => {
  res.json({
    status: 'online',
    node: 'seedthenode',
    timestamp: new Date().toISOString(),
    message: 'SeedTheNode is live 🚀'
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log('SeedTheNode API running on port ' + PORT);
});
