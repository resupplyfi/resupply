import json
import os
from pathlib import Path

def extract_abis():
    # Get project root and create abis directory
    root_dir = Path.cwd()
    abi_dir = root_dir / 'abis'
    out_dir = root_dir / 'out'
    
    # Create abis directory if it doesn't exist
    abi_dir.mkdir(exist_ok=True)
    
    # Iterate through all subdirectories in out/
    for subdir in out_dir.iterdir():
        if not subdir.is_dir():
            continue
            
        # Get first json file in subdirectory
        json_files = list(subdir.glob('*.json'))
        if not json_files:
            continue
            
        first_file = json_files[0]
        
        try:
            # Read and parse the JSON file
            with open(first_file, 'r') as f:
                content = json.load(f)
            
            # Extract the ABI if it exists
            if 'abi' in content:
                contract_name = first_file.stem  # Gets filename without extension
                abi_file = abi_dir / f'{contract_name}.json'
                
                # Write ABI to new file
                with open(abi_file, 'w') as f:
                    json.dump(content['abi'], f, indent=2)
                    
                print(f'Extracted ABI for {contract_name}')
                
        except Exception as e:
            print(f'Error processing {first_file}: {str(e)}')
    
    print('ABI extraction complete!')

def clean_abi_filenames(abi_dir: Path):
    """Remove version numbers from ABI filenames (format: Name.x.y.z.json)."""
    for file in abi_dir.glob('*.json'):
        name_parts = file.stem.split('.')
        if len(name_parts) > 1:
            # Take only the first part (before any dots)
            clean_name = name_parts[0]
            new_path = file.parent / f'{clean_name}.json'
            
            if new_path != file:
                try:
                    file.rename(new_path)
                    print(f'Renamed {file.name} to {new_path.name}')
                except Exception as e:
                    print(f'Error renaming {file.name}: {str(e)}')

if __name__ == '__main__':
    abi_dir = Path.cwd() / 'abis'
    clean_abi_filenames(abi_dir)