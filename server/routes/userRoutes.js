const express = require('express');
const router = express.Router();
const userController = require('../controllers/userController');

router.get('/users', userController.getUsers);
router.post('/users', userController.addUser);
router.delete('/users/:id', userController.deleteUser);

module.exports = router;

