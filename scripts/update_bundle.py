#!/usr/bin/env python3

from requests_html import HTMLSession
from multiprocessing import Pool
from re import match
from semver import VersionInfo
from functools import reduce
from os import path
from json import dumps as json_dumps

# The version of Terraform to add to the bundle.
TERRAFORM_VERSION = "0.11.13"

# The path to the file to generate.
BUNDLE_FILE_PATH = path.abspath(
    path.join(path.dirname(path.realpath(__file__)), path.pardir, "bundle.json")
)

# A list of providers to download.
DESIRED_PROVIDERS = [
    "acme",
    "aws",
    "azurerm",
    "cloudflare",
    "consul",
    "digitalocean",
    "dnsimple",
    "external",
    "gitlab",
    "google",
    "helm",
    "http",
    "kubernetes",
    "local",
    "mysql",
    "null",
    "postgresql",
    "template",
    "tls",
    "vault",
]


def get_provider(provider_link):
    """
    Adds an entry to the providers dict that represents a provider
    and associated versions to fetch with terraform-bundle.
    """
    version_string = get_latest_provider_version(provider_link)
    version = VersionInfo.parse(version_string)
    # Filter out any providers that don't have at least a minor release yet.
    if version.major == version.minor == 0:
        return
    desired_version = "~> {0}.{1}".format(version.major, version.minor)
    name = get_provider_name_from_link(provider_link)
    print(
        "Adding provider {0} with desired version '{1}'".format(name, desired_version)
    )
    return {name: [desired_version]}


def get_latest_provider_version(provider_link):
    """
    Gets the latest provider version given an absolute link to the provider
    release list on https://releases.hashicorp.com
    """
    session = HTMLSession()
    r = session.get(provider_link)
    version_links = [link for link in r.html.links if "provider" in link]
    return str(sorted(version_links, reverse=True)[0].split("/")[2])


def get_provider_name_from_link(provider_link):
    """
    Calculates the provider name based on an absolute link to the provider
    on https://releases.hashicorp.com
    """
    matches = match(r".*\/terraform-provider-([\w-]+)\/.*", provider_link)
    return matches.group(1)


if __name__ == "__main__":
    session = HTMLSession()
    r = session.get("https://releases.hashicorp.com")
    pool = Pool(processes=10)
    # Generate a list of absolute links to all providers that are listed as "desired"
    provider_links = [
        link
        for link in r.html.absolute_links
        if "terraform-provider" in link and
        any("{0}/".format(p) in link for p in DESIRED_PROVIDERS)
    ]

    # get_provider returns a dict, so the map() will return a list of dicts.
    # The reduce() flattens that list of dicts into a single dict containing
    # all items from the individual dicts. We can be reasonably sure that
    # there will be no collisions thanks to Hashicorp.
    results = pool.map(get_provider, provider_links)
    providers = reduce(lambda x, y: {**x, **y}, (r for r in results if r is not None))
    bundle_config = {
        "terraform": {"version": TERRAFORM_VERSION},
        "providers": providers,
    }
    with open(BUNDLE_FILE_PATH, "w+") as f:
        f.write(json_dumps(bundle_config, indent=2, sort_keys=True))
