import urllib.request
import json
import zipfile
import os

def get_wheel(project):
    url = f"https://pypi.org/pypi/{project}/json"
    with urllib.request.urlopen(url) as response:
        data = json.loads(response.read().decode())
        for release in data['urls']:
            if release['packagetype'] == 'bdist_wheel' and 'py3' in release['python_version']:
                return release['url']
    return None

def download_and_extract(project, target_dir):
    url = get_wheel(project)
    if not url:
        print(f"Could not find wheel for {project}")
        return
    
    filename = url.split('/')[-1]
    print(f"Downloading {url}...")
    urllib.request.urlretrieve(url, filename)
    
    print(f"Extracting {filename} to {target_dir}...")
    with zipfile.ZipFile(filename, 'r') as zip_ref:
        zip_ref.extractall(target_dir)
    os.remove(filename)

if __name__ == "__main__":
    target = "package"
    os.makedirs(target, exist_ok=True)
    download_and_extract("pg8000", target)
    download_and_extract("scramp", target)
    download_and_extract("python-dateutil", target)
    download_and_extract("six", target)
    download_and_extract("asn1crypto", target)
