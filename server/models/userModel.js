const db = require('../config/db');

const getUsers = (callback) => {
    db.query('SELECT * FROM users', callback);
};

const addUser = (user, callback) => {
    db.query('INSERT INTO users SET ?', user, callback);
};

const deleteUser = (id, callback) => {
    db.query('DELETE FROM users WHERE id = ?', [id], callback);
};

module.exports = { getUsers, addUser, deleteUser };

