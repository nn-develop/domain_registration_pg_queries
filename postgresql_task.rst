===============
POSTGRESQL TASK
===============

Use: postgresql database 9.6 or newer

Schema
======

Write an sql script which would create database schema described below. Create necessary table constraints.

Table ``domain`` representing fully qualified domain name registrations life time. Besides domain name it holds timestamps when domain name was registered and unregistered (deleted). Records of the given domain name cannot overlap in time (there can be only one record for given domain name which has not yet been marked as unregistered).

There is a bunch of flags which can be enabled on domain:
  - ``EXPIRED`` - domain is expired
  - ``OUTZONE`` - domain is not generated into zone (file)
  - ``DELETE_CANDIDATE`` - domain is marked to be deleted (unregistered) (e.g. by some external process)

Table ``domain_flag`` should represent history of flags being enabled and disabled on domains during time. For simplicity we can assume that individual flags are independent on each other and records for given domain can overlap in time. Each flag can be valid for some period of time. It always starts at specific time but the upper limit can be unbounded which means that it is valid indefinitely. We never change already inserted records with one exception: if upper limit is unbounded, it can be set to specific point in time but never to the past (at the time the change is made).


Implement as much as you can and if you think that some part of the task cannot be implemented explain it in your solution.

Propose (not necessarily implement) other possible constraints and enhancements which could be created and not have been explicitly mentioned in the task description.


Queries
=======

Write a ``SELECT`` query which will return fully qualified domain name of domains which are currently (at the time query is run) registered and do not have and active (valid) expiration (``EXPIRED``) flag.

Write a ``SELECT`` query which will return fully qualified domain name of domains which have had active (valid) ``EXPIRED`` and ``OUTZONE`` flags (means both flags and not necessarily at the same time) in the past (relative to the query run time).

If needed insert some testing data.
