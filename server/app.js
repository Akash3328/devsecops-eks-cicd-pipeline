const express = require('express');
const app = express();
const userRoutes = require('./routes/userRoutes');

app.use(express.json());
app.use(express.static('client/public')); // Serve static files from client

app.use('/api', userRoutes);

module.exports = app;

