# API Drift Watch

API docs say one thing and the API does another. API Drift Watch calls real endpoints on a schedule and compares every response with the OpenAPI spec. A live dashboard shows where they drift apart: missing fields, wrong types, unexpected nulls, invalid values, undocumented status codes and fields the spec never mentions.

To check your own API without setting anything up, paste its spec and a response on the compare page.

It is built with Elixir, Phoenix LiveView, Oban and PostgreSQL.

![Dashboard](docs/dashboard.png)

## What it found in real APIs

The app watches four public APIs. On its first runs it found two places where the API and its own spec disagree. Both were checked by hand against the spec and a raw `curl`.

| API | Drift | Details |
|---|---|---|
| Open-Meteo forecast | extra field `#/current_units/interval` | The response sends `"interval": "seconds"` in `current_units`. The spec documents `interval` in `current` but forgot it in `current_units`. |
| Swagger Petstore 3.1 | invalid value `#/availableInstances` | Every pet comes back with `availableInstances: 0`, while the spec says `exclusiveMinimum: 1`. |

GitHub (`GET /repos/{owner}/{repo}`) and PokeAPI (`GET /api/v2/pokemon/{id}/`) matched their specs.

| API | Spec | Check | Every |
|---|---|---|---|
| [Open-Meteo](https://open-meteo.com) | 3.1, YAML | `GET /v1/forecast` for De Bilt | 15 min |
| [PokeAPI](https://pokeapi.co) | 3.1, YAML | `GET /api/v2/pokemon/pikachu/` | 30 min |
| [GitHub REST API](https://docs.github.com/rest) | 3.1, JSON, 14 MB | `GET /repos/phoenixframework/phoenix` | 15 min |
| [Swagger Petstore 3.1](https://petstore31.swagger.io) | 3.1, JSON | `GET /pet/1` | 10 min |

The intervals are polite on purpose: GitHub allows 60 calls an hour without a token and PokeAPI asks clients to cache.

![Real APIs on the dashboard](docs/real_apis.png)

## What counts as drift

| Kind | Example |
|---|---|
| Missing field | the spec marks `name` as required and the response has no `name` |
| Wrong type | the spec says `temperature_c` is a number and the API sends `"12.4"` |
| Unexpected null | `location.lat` is `null` while the spec does not allow null |
| Invalid value | `status` is `"maintenance"` but the spec lists only `online` and `offline` |
| Extra field | the response has `humidity_pct` and the spec does not describe it |
| Undocumented status | the API answers `500` and the spec only documents `200` and `404` |

Every drift has a JSON path (like `#/location/lat`), what the spec expected and what the API sent.

## Try it

You need Elixir 1.20 with OTP 29 (see `.tool-versions`) and PostgreSQL with the user `postgres` and password `postgres`.

```bash
mix setup          # dependencies, database, demo data and assets
mix phx.server
```

Open http://localhost:4000. Within a minute the scheduler runs the first checks. Press Run now to run one right away. The four public APIs need internet access.

Next to the public APIs the app watches the drifty API that ships with it: a small weather station API with its own spec at `/drifty/openapi.json`. About half of its responses break the spec on purpose, so there is always something to see. Ask for a specific drift with `?drift=wrong_type`, for example http://localhost:4000/drifty/stations/1?drift=wrong_type.

![Check detail](docs/check.png)

## Compare your own spec

Press Compare a response on the dashboard (or open http://localhost:4000/compare) and paste an OpenAPI 3.1 spec (JSON or YAML) and a response body. Pick the operation and the status code and the page lists every drift. It runs the same checker as the watched APIs. Nothing is fetched and nothing is stored, so it also works for private APIs the server could never reach. Press Try the example to load the drifty spec with a response that has five drifts.

![Compare page](docs/compare.png)

## How it works

```
Oban cron, every minute
  └─ SchedulerWorker   queues every check that is due
       └─ CheckWorker  loads the spec, calls the endpoint, stores the run
            ├─ Specs     finds the response schema for the method, path and status
            ├─ Checker   compares the response with the schema
            └─ Monitoring stores the run, updates the drift history, broadcasts on PubSub
                 └─ DashboardLive and CheckLive update live
```

| Module | Job |
|---|---|
| `DriftWatch.Specs` | downloads a spec, finds an operation and the schema for a status code (exact code, then `5XX` style ranges, then `default`) |
| `DriftWatch.Checker` | `compare/4` turns a status and a body into drifts without any IO. `run/3` adds the HTTP call and the timing |
| `DriftWatch.Checker.SchemaErrors` | maps validator errors to drift kinds |
| `DriftWatch.Checker.ExtraFields` | finds fields the schema never mentions |
| `DriftWatch.Monitoring` | the context for APIs, checks, runs and drift history |
| `DriftWatch.Comparison` | the compare page: size limits, parsing and comparing a pasted spec and response |
| `DriftWatch.Sandbox` | runs work on untrusted input in a process with a memory cap and a time limit |
| `DriftWatch.Workers.*` | the scheduler and the check runner |
| `DriftWatch.Drifty` | the demo API that breaks its own spec |

## Decisions

**JSV validates the schemas.** OpenAPI 3.1 schemas are JSON Schema 2020-12. I compared four options:

| Library | Why not or why |
|---|---|
| open_api_spex | built to document your own Phoenix API, supports OpenAPI 3.0 only and turns spec strings into atoms when it loads a spec. Its own docs warn against loading untrusted specs that way and this app loads specs from the internet. |
| ex_json_schema | supports JSON Schema drafts 4 to 7 and not 2020-12 |
| Oaskit | OpenAPI 3.1 and built on JSV, but focused on validating requests to your own Phoenix app. Too much framework for this job. |
| **JSV** | full 2020-12 support, passes the official JSON Schema test suite, works on plain maps with string keys and reports every error with its JSON path |

**Our own small layer on top.** A validator answers "is this valid". Drift needs more: which kind of problem and where. `SchemaErrors` keeps the leaf errors (`required`, `type`, `enum` and other value rules) and skips the errors that only say a child failed. For `oneOf` and `anyOf` every branch reports its own errors, which would blame the response for branches it never meant to match. So we drop branches where the value has the wrong type altogether and report the branch with the fewest drifts.

**Extra fields need a separate pass.** JSON Schema allows extra properties by default, so no validator reports them. Adding `unevaluatedProperties: false` to every schema looked tempting, but it breaks `allOf`: a shared component would then reject the properties that the other branch adds. `ExtraFields` walks the response next to the schema instead and counts properties from every composed branch as documented. Objects that allow extra fields on purpose (`additionalProperties`) are left alone.

**A failed call is a result, not a failed job.** Timeouts, connection errors and specs that do not load are stored as runs with an error. Oban does not retry them, because a retry would hide exactly the flaky behaviour this app wants to show. Req retries are off for the same reason.

**Drift history is its own table.** A run is an immutable log entry. A drift is a distinct mismatch of a check (kind, path, expected and actual) with first seen, last seen and a count. Runs link to the drifts they saw. "Since when is this broken" is then one row and not a scan over every run. For type drifts we store the JSON type and not the value, so a changing temperature stays one drift.

**Scheduling decides from the database every minute.** The cron job asks which checks are due and queues them. A restart, a changed interval or a lost job fixes itself on the next tick. Check jobs are unique per check, so a slow API never piles up jobs.

**The demo API lives in the app.** A demo should not depend on a public API that happens to behave that day. The drifty API also makes the best test: for every drift it can produce, a test asserts that the checker finds exactly that drift.

**Tests do not touch the network.** All HTTP goes through `DriftWatch.HTTP`, so tests stub it with `Req.Test`. Some tests route requests into the app's own endpoint and run the whole stack: Oban job, HTTP, spec, checker and database.

**Check the real specs before writing code for them.** The plan was to convert OpenAPI 3.0 specs first. Downloading the candidates showed that all four publish a 3.1 spec, so the conversion was not needed. What they did need was not in the plan:

* YAML support, because Open-Meteo and PokeAPI publish YAML. YAML reads an unquoted `200:` as a number, so every key becomes a string after parsing.
* A base URI. Petstore 3.1 references schemas by a relative `$id` like `/api/v31/components/schemas/petdetails`, which JSV can only place when the document has an absolute `$id`. OpenAPI 3.1 says relative references resolve against the URL the spec was loaded from, so that URL becomes the `$id`.
* Keeping big specs out of page loads. GitHub's spec is 14 MB, so the `spec` column is not loaded by normal queries and is only read when a check runs. The dashboard stays at a few milliseconds.

**Pasted specs run in a sandbox.** Anyone can paste a spec on the compare page, so it is untrusted input. Three things could go wrong and each has its own limit:

* Size. Specs and bodies over 1 MB are refused before parsing.
* Memory. YAML aliases can point at other aliases. Less than 1 KB of nested aliases expands to a billion strings. The BEAM can cap the heap of one process, so parsing and comparing run in a separate process with a 128 MB cap. When it grows past that the process is killed and the page shows an error. The page itself keeps running.
* Time. A schema can hold a regex that takes forever. The work gets 5 seconds.

At most 4 of these processes run at the same time, so the worst case for the whole node is about half a GB. I measured the limits first: the 318 KB PokeAPI YAML spec needs between 16 and 32 MB to parse.

**Specs never create atoms.** Atoms are never garbage collected, so creating them from outside input can eventually crash the node. JSV has its own `x-jsv-cast` keyword that turns validated strings into atoms. A spec could use it to turn every response value into a new atom. The checker builds schemas with `atoms: false` and validates with `cast: false`. A test makes sure such a spec creates no atom. A malformed `x-jsv-cast` also made JSV raise instead of returning an error, so the checker turns that into an invalid schema result.

**A strict Content Security Policy.** Everything loads from the app itself and nothing runs inline. The theme script that Phoenix puts inline in the layout is a separate file for that reason.

## Quality checks

```bash
mix precommit      # compile with warnings as errors, unused deps, format, Credo, Sobelow, tests
mix dialyzer
mix deps.audit     # known vulnerable dependencies
```

GitHub Actions runs all of them on every push. Formatting uses Styler.

## Limits and next steps

* Only OpenAPI 3.1 and 3.2. Specs in 3.0 use `nullable` and need a conversion step.
* References to other files are not followed. References by `$id` inside the spec work for validation, but the extra field check skips the schemas it can only reach that way.
* Watched specs come from URLs the operator sets up in the seeds, so they are parsed without the sandbox and without a size limit.
* Response headers and content types are not compared yet.
* There is no UI to add an API or a check yet. The seeds add them.
* Watch mode for your own APIs is the next big step: add an API and its checks in the UI and let the scheduler run them. Most of it exists already. What it needs on top is a block on private and local addresses, so nobody can make the server call its own network (SSRF). It also needs a limit on how often each check runs and the sandbox around spec downloads.
