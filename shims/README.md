# Offline Shims

In our normal applications, persistence and some data collection happen over a
set of APIs handled by the backend servers. These, obviously, do not exist in an
offline environment. Instead, the API calls are intercepted by the offline
application and handled locally.

## Interception

The normal application makes asynchronous calls to the backend APIs typically
through the `/api/*` or `/v3/*` routes (although some data collection happens using other
routes and 1 pixel images.) For the offline application, all outgoing
asynchronous requests are captured. We do this anyway to update outgoing
requests using absolute paths (`/foo/bar`) to use relative paths
(`../../../foo/bar`, etc). The added code checks for an API route and does not
issue the network request. Instead, it mocks a response and handles the API
call in some reasonable way entirely within the app itself.

## API

The `callApi` function in `shims/shim.js` implements the logic for each API
call. Every API call responds with JSON.

### `/api/v1/users/current`

Responses with the current user account information, if any. If no user, it
responds with a `{ is_signed_in: false }` document.

### `/api/example_solutions`

This always gets called to retrieve any example solutions that are only usable
by folks with a teacher panel. So, students would not necessarily see these. So,
the response mocked is just an empty array.

### `/api/hidden_lessons`

This would get the lessons hidden from students and is only applicable for
teachers as well. This is always retrieved for student views for some reason and
so also just gets a mocked empty response.

### `/api/user_app_options`

This is the main blob of metadata for the level and the current user. This
reports the channel id and whether or not the account is signed in.

### `/api/channels/<channel>`

Returns metadata about the 'channel' which for levels is the level progress data.
This response has an initial state when the level has never been done before.
The way the application kind of checks that there is previously persisted data
(and versions of files, etc) is to check the `migratedToS3` field of this
response. When `true`, there are versions to pull. So, this response mocks that
if we have any versions locally stored.

The response also reports the relationship between the arbitrary "channel" idea
and the underlying "level" being viewed in the `level` field and `projectType`
field. The `thumbnail` would be an image representing the level that is used on
the site to preview the level/game/etc. These are all handled and stored in a
way that can be retrieved on a subsequent `GET` request.

### `/api/sources/<file>` and `/api/files/<file>`

When this is used via a `GET` request, the file at the path given by `<file>`
is retrieved. When it sees a `PUT` or `POST`, the file is updated. The result
of a written file is a JSON document describing the saved version. This
response is mocked to provide a random string as the version, the file name and
size, and the timestamp for when it was written.

This information is also then stored in a way that can be negotiated through the
versioning api calls. Particular versions can be accessed when the api call
has a `version` argument, such as `/api/sources/main.json?version=<versionId>`,
which results in that version of the file being loaded.

Thumbnails are also written to via this api path. When we detect that, we
specifically ensure it is stored in a way that is reported on a `/api/channels/`
call.

### `/api/sources/<file>/versions`

This results in an array of versions of the given file. Each version info block
in this array reports the `versionId` which is the hash identifying that
version, and a `lastModified` field with the date it was written.

This is used by the version modal to show the previous versions and allow
access to that history.

### `/api/sources/<file>/restore?version=<versionId>`

Normally, navigating the version history results in a read-only view of the
level at that time. The `restore` api call will restore the file to the one
at the provided version. This essentially just "writes" the file... causing a
new version record appended to the history with the content of this
particular version. The `versionId` is the same since the file content is the
same, but now the version record is in two positions in the version history.
