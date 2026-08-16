const express = require('express');
const router = express.Router();
const db = require('../config/db'); // Adjust the path if needed

// GET all users
router.get('/', (req, res) => {
  db.query('SELECT * FROM users', (err, results) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.json(results);
  });
});

// POST (Create) new user
router.post('/', (req, res) => {
  const { name, email, role } = req.body;
  db.query(
    'INSERT INTO users (name, email, role) VALUES (?, ?, ?)',
    [name, email, role],
    (err) => {
      if (err) {
        return res.status(500).json({ error: err.message });
      }
      res.sendStatus(201);
    }
  );
});

// PUT (Update) user
router.put('/:id', (req, res) => {
  const { name, email, role } = req.body;
  db.query(
    'UPDATE users SET name = ?, email = ?, role = ? WHERE id = ?',
    [name, email, role, req.params.id],
    (err) => {
      if (err) {
        return res.status(500).json({ error: err.message });
      }
      res.sendStatus(200);
    }
  );
});

// DELETE user
router.delete('/:id', (req, res) => {
  db.query('DELETE FROM users WHERE id = ?', [req.params.id], (err) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    res.sendStatus(200);
  });
});

module.exports = router;

