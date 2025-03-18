"""
ABI Extractor for Solidity Projects
==================================

This script extracts ABIs from compiled Solidity contract artifacts and saves them as separate JSON files.
It's designed to work with Foundry/Forge compiled outputs, but can work with any similar JSON artifacts.

Usage:
------
1. Run directly: 
   python extract_abis.py

2. Import and use in another script:
   from extract_abis import extract_abis
   extract_abis(source_dir='out', output_dir='abis', include_paths=['src/'])

Configuration:
-------------
- source_dir: Directory containing compiled contract JSON files (default: 'out')
- output_dir: Directory where ABI files will be saved (default: 'abis')
- include_paths: List of source paths to include (default: ['src/'])
- exclude_paths: Paths that are always excluded (configured in extract_abis function):
  - node_modules
  - @openzeppelin
  - lib/
  - src/interfaces/
  - src/libraries/
  - src/dependencies/
  - test/
  - script/

Output:
-------
- Creates ABI files in the specified output directory
- Files are named with 'I' prefix (e.g., IMyContract.json)
- Version numbers are automatically cleaned from filenames

Notes:
------
- Requires the compiled contract JSON files to contain metadata with compilationTarget
- Skips files that don't match include_paths or match exclude_paths
- Automatically creates the output directory if it doesn't exist
"""

import json
import os
from pathlib import Path

def extract_abis(source_dir: str = 'out', output_dir: str = 'abis', include_paths: list[str] = None):
    # Get project root and create abis directory
    root_dir = Path.cwd()
    abi_dir = root_dir / output_dir
    out_dir = root_dir / source_dir
    
    # Default include paths if none provided
    if include_paths is None:
        include_paths = ['src/']
    
    # Paths to explicitly exclude
    exclude_paths = [
        'node_modules',
        '@openzeppelin',
        'lib/',
        'src/interfaces/',
        'src/libraries/',
        'src/dependencies/',
        'test/',
        'script/'
    ]
    
    print(f"Looking in directory: {out_dir}")
    print(f"Output directory: {abi_dir}")
    print(f"Including paths: {include_paths}")
    print(f"Excluding paths: {exclude_paths}")
    
    # Create abis directory if it doesn't exist
    abi_dir.mkdir(exist_ok=True)
    
    if not out_dir.exists():
        print(f'Source directory {source_dir} does not exist!')
        return

    # Process all json files in the directory
    json_files = list(out_dir.glob('**/*.json'))
    print(f"Found {len(json_files)} JSON files")
    
    for json_file in json_files:
        print(f"\nProcessing: {json_file}")
        try:
            # Read and parse the JSON file
            with open(json_file, 'r') as f:
                content = json.load(f)
            
            source_path = None
            
            # Look for source path in metadata.settings.compilationTarget
            if 'metadata' in content:
                metadata = content['metadata']
                # Handle string metadata
                if isinstance(metadata, str):
                    try:
                        metadata = json.loads(metadata)
                    except:
                        pass
                
                # Try to find source path in compilationTarget
                if isinstance(metadata, dict) and 'settings' in metadata:
                    settings = metadata['settings']
                    if 'compilationTarget' in settings:
                        source_paths = list(settings['compilationTarget'].keys())
                        if source_paths:
                            source_path = source_paths[0]
            
            if not source_path:
                print("No source path found in compilation target")
                continue
                
            print(f"Source path: {source_path}")
            
            # Skip if path contains any excluded patterns
            if any(exclude in source_path for exclude in exclude_paths):
                print(f"Skipping: matches exclude pattern")
                continue
            
            # Skip if we have include_paths and this file isn't in them
            if not any(source_path.startswith(path) for path in include_paths):
                print(f"Skipping: not in include_paths")
                continue
            
            # Extract the ABI if it exists
            if 'abi' in content:
                # Add 'I' prefix for interface naming
                contract_name = 'I' + json_file.stem
                abi_file = abi_dir / f'{contract_name}.json'
                
                # Write ABI to new file
                with open(abi_file, 'w') as f:
                    json.dump(content['abi'], f, indent=2)
                    
                print(f'Extracted ABI for {contract_name} (from {source_path})')
            else:
                print("No ABI found in file")
                    
        except Exception as e:
            print(f'Error processing {json_file}: {str(e)}')
    
    print('\nABI extraction complete!')

def clean_abi_filenames(abi_dir: Path):
    """Remove version numbers from ABI filenames (format: IName.x.y.z.json)."""
    for file in abi_dir.glob('*.json'):
        name_parts = file.stem.split('.')
        if len(name_parts) > 1:
            # Take only the first part (before any dots), preserve 'I' prefix
            clean_name = name_parts[0]
            new_path = file.parent / f'{clean_name}.json'
            
            if new_path != file:
                try:
                    file.rename(new_path)
                    print(f'Renamed {file.name} to {new_path.name}')
                except Exception as e:
                    print(f'Error renaming {file.name}: {str(e)}')

if __name__ == '__main__':
    # Example usage with specific source paths to include
    include_paths = [
        'src/',  # include all contracts in src/
        'contracts/'  # include all contracts in contracts/
    ]
    
    extract_abis(source_dir='out', output_dir='abis', include_paths=include_paths)
    clean_abi_filenames(Path.cwd() / 'abis')