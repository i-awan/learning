import smbclient
import os

# SMB connection configuration
smbclient.register_session(server='nas_server_address', username='your_username', password='your_password')

# Define source and target paths
nas_source_dir = r"\\nas_server\source_folder"  # Source folder on NAS (SMB path)
nas_target_dir = r"\\nas_server\target_folder"  # Target folder on NAS (SMB path)
source_file_name = "data.csv"  # Name of the source file
source_file_path = os.path.join(nas_source_dir, source_file_name)

# Step 1: Open and read the CSV file from NAS
with smbclient.open_file(source_file_path, mode='rb') as file:
    file_contents = file.read()

# Step 2: Create a new file with the 'temp' prefix
temp_file_name = f"temp_{source_file_name}"
temp_file_path = os.path.join(nas_source_dir, temp_file_name)

# Write the contents of the source file to the new temp file
with smbclient.open_file(temp_file_path, mode='wb') as temp_file:
    temp_file.write(file_contents)

# Step 3: Copy the 'temp' file to another folder in NAS
# First, create the target directory if it doesn't exist
if not smbclient.exists(nas_target_dir):
    smbclient.mkdir(nas_target_dir)

# Copy the temp file to the target directory
target_temp_file_path = os.path.join(nas_target_dir, temp_file_name)
with smbclient.open_file(temp_file_path, mode='rb') as src_file:
    with smbclient.open_file(target_temp_file_path, mode='wb') as dst_file:
        dst_file.write(src_file.read())

# Step 4: Rename the copied file by removing the 'temp' prefix
final_file_path = os.path.join(nas_target_dir, source_file_name)
smbclient.rename(target_temp_file_path, final_file_path)

print(f"File has been successfully copied and renamed to {final_file_path}")

# Clean up and close the session
smbclient.reset_session(server='nas_server_address')
