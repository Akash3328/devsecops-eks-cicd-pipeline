const userModel = require('../models/userModel');

const getUsers = (req, res) => {
    userModel.getUsers((err, results) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(results);
    });
};

const addUser = (req, res) => {
    userModel.addUser(req.body, (err, result) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ id: result.insertId, ...req.body });
    });
};

const deleteUser = (req, res) => {
    userModel.deleteUser(req.params.id, (err) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ message: 'User deleted' });
    });
};

module.exports = { getUsers, addUser, deleteUser };

