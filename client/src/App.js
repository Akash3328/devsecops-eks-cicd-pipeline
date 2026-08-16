// client/src/App.js
import React, { useState, useEffect } from 'react';
import './App.css';

function App() {
    const [users, setUsers] = useState([]);
    const [name, setName] = useState('');
    const [email, setEmail] = useState('');
    const [role, setRole] = useState('');

    // Fetch users from the backend
    useEffect(() => {
        fetch('/api/users')
            .then(res => res.json())
            .then(data => setUsers(data))
            .catch(err => console.error('Error fetching users:', err));
    }, []);

    // Handle form submission
    const handleSubmit = (e) => {
        e.preventDefault();

        const newUser = { name, email, role };

        fetch('/api/users', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(newUser),
        })
            .then(res => res.json())
            .then(data => {
                setUsers([...users, data]);
                setName('');
                setEmail('');
                setRole('');
            })
            .catch(err => console.error('Error adding user:', err));
    };

    return (
        <div className="app">
            <div className="navbar">
                <div className="brand">DevOps Shack</div>
                <div className="nav-links">
                    <a className="home" href="/">Home</a>
                    <a className="youtube" href="https://www.youtube.com/@devopsshack/videos">YouTube</a>
                    <a className="courses" href="https://www.devopsshack.com/">Courses</a>
                    <a className="telegram" href="https://t.me/+9roGPjX1YI42Yzdl">Telegram</a>
                    <a className="instagram" href="https://www.instagram.com/devopsshack/">Instagram</a>
                </div>
            </div>
            <h1>DevOps Shack User Management App</h1>
            <div className="form-container">
                <input type="text" placeholder="New user name" value={name} onChange={(e) => setName(e.target.value)} />
                <input type="email" placeholder="New user email" value={email} onChange={(e) => setEmail(e.target.value)} />
                <select value={role} onChange={(e) => setRole(e.target.value)}>
                    <option value="">Select role</option>
                    <option value="Admin">Admin</option>
                    <option value="User">User</option>
                </select>
                <button onClick={handleSubmit}>Add User</button>
            </div>
            <ul className="user-list">
                {users.map(user => (
                    <li key={user.id} className="user-item">
                        <span>{user.name} ({user.email}) - {user.role}</span>
                        <div className="edit-container">
                            <button>Edit</button>
                            <button>Delete</button>
                        </div>
                    </li>
                ))}
            </ul>
        </div>
    );
}

export default App;

