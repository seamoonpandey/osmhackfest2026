# API Integration Notes

The frontend has been updated to integrate with the new API endpoints defined in the backend.

## Endpoints Integrated

### 1. `GET /issues` (Not Implemented on Backend)

- **Note**: The backend does not currently support fetching individual issue reports.
- **Behavior**: The app uses locally stored reports instead.
- **Future**: If implemented, it should return a GeoJSON FeatureCollection.

### 2. `GET /roads` (formerly `/segments`)

- **Format**: GeoJSON FeatureCollection
- **Use**: Fetches road segments with risk data.
- **Mapping**:
  - `geometry.coordinates` -> `points` (LineString)
  - `properties.risk` -> `priorityScore` (Normalized 0-100 to 0-5)
  - `properties.highway` / `properties.road_class` -> `type`

### 3. `POST /report` (formerly `/reports`)

- **Format**: `multipart/form-data`
- **Fields**:
  - `road_id` (defaulted to 0 for now)
  - `issue_type`
  - `severity` (1-5)
  - `lat`
  - `lon`
  - `photo` (file upload)

## Mocking

The `MockInterceptor` has been updated to strictly mimic these new endpoints and response formats, allowing the frontend to be tested independently of the backend.
