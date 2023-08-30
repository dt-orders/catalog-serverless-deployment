from opentelemetry.sdk.resources import Resource
from opentelemetry.semconv.resource import ResourceAttributes
from dynatrace.opentelemetry.tracing.api import configure_dynatrace

tracer_provider = configure_dynatrace(
    resource=Resource.create({ResourceAttributes.SERVICE_NAME: "CatalogService"})
)

