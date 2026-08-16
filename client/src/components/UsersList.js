import React, { useState, useEffect } from 'react';
import { getUsers, deleteUser } from '../api/users';
import UserItem from './UserItem'; // Assuming you have a UserItem component

function UsersList() {
  const [users, setUsers] = useState([]);

  useEffect(() => {
    getUsers()
      .then(response => {
        setUsers(response.data);
      })
      .catch(error => {
        console.error('Error fetching users:', error);
      });
  }, []);

  const handleDelete = (id) => {
    deleteUser(id)
      .then(() => {
        setUsers(users.filter(user => user.id !== id));
      })
      .catch(error => {
        console.error('Error deleting user:', error);
      });
  };

  return (
    <div>
      <h1>Users</h1>
      <ul>
        {users.map(user => (
          <UserItem key={user.id} user={user} onDelete={handleDelete} />
        ))}
      </ul>
    </div>
  );
}

export default UsersList;

