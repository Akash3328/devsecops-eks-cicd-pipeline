import React from 'react';

function UserItem({ user, onDelete }) {
  return (
    <div>
      <span>{user.name} - {user.email} - {user.role}</span>
      <button onClick={() => console.log('Edit functionality')}>Edit</button>
      <button onClick={() => onDelete(user.id)}>Delete</button>
    </div>
  );
}

export default UserItem;

