document.addEventListener('DOMContentLoaded', () => {
  fetchUsers();

  // Add User
  document.getElementById('addUserForm').addEventListener('submit', function(event) {
    event.preventDefault();
    const name = document.getElementById('name').value;
    const email = document.getElementById('email').value;
    const role = document.getElementById('role').value;

    fetch('/api/users', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ name, email, role }),
    })
    .then(response => response.json())
    .then(data => {
      console.log('Success:', data);
      fetchUsers(); // Refresh the user list
    })
    .catch(error => {
      console.error('Error:', error);
    });
  });

  // Event delegation for Edit and Delete
  document.getElementById('userList').addEventListener('click', function(event) {
    if (event.target.classList.contains('edit')) {
      const userId = event.target.getAttribute('data-id');
      const name = prompt('Enter new name:');
      const email = prompt('Enter new email:');
      const role = prompt('Enter new role (User/Admin):');
      if (name && email && role) {
        fetch(`/api/users/${userId}`, {
          method: 'PUT',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ name, email, role }),
        })
        .then(response => response.json())
        .then(data => {
          console.log('Updated:', data);
          fetchUsers(); // Refresh the user list
        })
        .catch(error => {
          console.error('Error:', error);
        });
      }
    }

    if (event.target.classList.contains('delete')) {
      const userId = event.target.getAttribute('data-id');
      if (confirm('Are you sure you want to delete this user?')) {
        fetch(`/api/users/${userId}`, {
          method: 'DELETE',
        })
        .then(response => response.json())
        .then(data => {
          console.log('Deleted:', data);
          fetchUsers(); // Refresh the user list
        })
        .catch(error => {
          console.error('Error:', error);
        });
      }
    }
  });
});

// Fetch and display users
function fetchUsers() {
  fetch('/api/users')
    .then(response => response.json())
    .then(users => {
      const userList = document.getElementById('userList');
      userList.innerHTML = '';
      users.forEach(user => {
        const li = document.createElement('li');
        li.innerHTML = `
          ${user.name} (${user.email}) - ${user.role}
          <button class="edit" data-id="${user.id}">Edit</button>
          <button class="delete" data-id="${user.id}">Delete</button>
        `;
        userList.appendChild(li);
      });
    })
    .catch(error => {
      console.error('Error fetching users:', error);
    });
}

