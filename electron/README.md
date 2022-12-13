# Electron Builds

We can take any of our packaged modules and wrap them as an electron
application. Use the `make-electron-win.sh`, etc, scripts to add a zipped
distribution of the electron app in `dist/releases`.

## Usage

After using `package.sh` on a module, in this case `hello-world-space-2022`,
you can create an electron app using this command:

```
./make-electron-win.sh hello-world-space-2022
```

Would create `dist/releases/hello-world-space-2022_1-win32-x64.zip`.

## Running the electon app

The zip file contains an executable based on the course. So for
`hello-world-space-2022`, the exe would be `hello-world-space-2022_1.exe`.

## How it works

The electon app is essentially the unzipped distribution of Electron with the
static module placed in the `resources/app` path, which is conventional for
Electron applications.

Then, there is a `main.js` that we maintain in this repository that is copied
into the root of the `app` path that the Electron app looks for and runs
initially. This sets up the basic options like the size of the window. This
file can be modified in the unzipped distribution which is useful for
debugging.

Speaking of that, the `main.js` contains a commented-out line that would open
the dev tools pane. Just uncomment that and run the application's executable.
