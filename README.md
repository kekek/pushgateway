# Prometheus Pushgateway

[![Build Status](https://travis-ci.org/prometheus/pushgateway.svg)][travis]
[![CircleCI](https://circleci.com/gh/prometheus/pushgateway/tree/master.svg?style=shield)][circleci]
[![Docker Repository on Quay](https://quay.io/repository/prometheus/pushgateway/status)][quay]
[![Docker Pulls](https://img.shields.io/docker/pulls/prom/pushgateway.svg?maxAge=604800)][hub]

Prometheus Pushgateway的存在是为了允许临时任务和批处理作业向Prometheus公开其指标。 由于这类工作可能存在的时间不够长，无法被取消，因此可以将其指标推送到Pushgateway。 然后，Pushgateway将这些指标公开给Prometheus。

## non-goal

The Pushgateway 明显不是聚合器或计数器，而是一个指标缓存。它没有[statsd](https://github.com/etsy/statsd)的语义. 推送的指标与在程序中抓到的指标完全相同。 如果您需要分布式计数器, 您可以尝试一下statsd 结合 [Prometheus statsd exporter](https://github.com/prometheus/statsd_exporter), 或者[Weavework's aggregation gateway](https://github.com/weaveworks/prom-aggregation-gateway).通过积累更多的经验，Prometheus项目也许有一天能够提供与Pushgateway分离甚至是其一部分的本地解决方案。

对于机器级别的指标, the[textfile](https://github.com/prometheus/node_exporter/blob/master/README.md#textfile-collector)Node exporter的收集器通常更为合适。Pushgateway 更适合服务级别的指标。

Pushgateway 不是事件存储器. 当然，你可以使用Prometheus作为[Grafana annotations](http://docs.grafana.org/reference/annotations/)的数据源，来跟踪比如 发布事件等一类的东西。

A while ago, we
[decided to not implement a “timeout” or TTL for pushed metrics](https://github.com/prometheus/pushgateway/issues/19)
because almost all proposed use cases turned out to be anti-patterns we
strongly discourage. You can follow a more recent discussion on the
[prometheus-developers mailing list](https://groups.google.com/forum/#!topic/prometheus-developers/9IyUxRvhY7w).

## Run it

Download binary releases for your platform from the
[release page](https://github.com/prometheus/pushgateway/releases) and unpack
the tarball.

If you want to compile yourself from the sources, you need a working Go
setup. Then use the provided Makefile (type `make`).

For the most basic setup, just start the binary. To change the address
to listen on, use the `--web.listen-address` flag (e.g. "0.0.0.0:9091" or ":9091").
By default, Pushgateway does not persist metrics. However, the `--persistence.file` flag
allows you to specify a file in which the pushed metrics will be
persisted (so that they survive restarts of the Pushgateway).

### Using Docker

You can deploy the Pushgateway using the [prom/pushgateway](https://registry.hub.docker.com/u/prom/pushgateway/) Docker image.

For example:

```bash
docker pull prom/pushgateway

docker run -d -p 9091:9091 prom/pushgateway
```

## 使用

### 将 Pushgateway 配置为收集目标

The Pushgateway has to be configured as a target to scrape by Prometheus, using
one of the usual methods. _However, you should always set `honor_labels: true`
in the scrape config_ (see [below](#about-the-job-and-instance-labels) for a
detailed explanation).

### 客户端库

Prometheus客户端库应该具有推送注册指标到Pushgateway的能力。
通常客户端会提供指标度量，被动的等待prometheus服务器来收集。 但是客户端库实现了push函数，支持主动推送指标。
当调用push函数时， 客户端库会使用下面描述的API主动推送指标到Pushgateway。

### 命令行

使用Prometheus文本协议, 推送指标是如此的方便，以至于没有单独提供cli程序. 比如使用命令行的http工具`curl`. 或其他您喜欢的脚本语言提供的http工具。

*Note ：文本协议中, 必须以换行符 ('LF' or '\n')结尾。使用其他的方式结尾, 例如 'CR'，'\r', 'CRLF'， '\r\n', 将会返回一个协议错误。*

推送的指标按分组管理， 分组的名字由任意数量的标签确定， 这些标签必须的第一个必须是job标签。这些分组通过web接口很容易检查。

*标签值中特殊字符的含义请参考[URL section](#url)。*

Examples:

* Push a single sample into the group identified by `{job="some_job"}`:

        echo "some_metric 3.14" | curl --data-binary @- http://pushgateway.example.org:9091/metrics/job/some_job

  Since no type information has been provided, `some_metric` will be of type `untyped`.

* Push something more complex into the group identified by `{job="some_job",instance="some_instance"}`:

        cat <<EOF | curl --data-binary @- http://pushgateway.example.org:9091/metrics/job/some_job/instance/some_instance
        # TYPE some_metric counter
        some_metric{label="val1"} 42
        # TYPE another_metric gauge
        # HELP another_metric Just an example.
        another_metric 2398.283
        EOF

  Note how type information and help strings are provided. Those lines
  are optional, but strongly encouraged for anything more complex.

* Delete all metrics in the group identified by
  `{job="some_job",instance="some_instance"}`:

        curl -X DELETE http://pushgateway.example.org:9091/metrics/job/some_job/instance/some_instance

* Delete all metrics in the group identified by `{job="some_job"}` (note that
  this does not include metrics in the
  `{job="some_job",instance="some_instance"}` group from the previous example,
  even if those metrics have the same job label):

        curl -X DELETE http://pushgateway.example.org:9091/metrics/job/some_job
        
* Delete all metrics in all groups (requires to enable the admin API via the command line flag `--web.enable-admin-api`):

        curl -X PUT http://pushgateway.example.org:9091/api/v1/admin/wipe

### 关于 job 和 instance 标签

Prometheus服务器将在每个已收集指标上附加一个`job`标签和一个`instance`标签。 `job`标签的值来自于prometheus抓取目标的配置。 当您将Pushgateway配置为Prometheus服务器的抓取目标时，您可能会选择工作名称，例如`pushgateway`。`instance`标签的值会自动设置为要抓取的目标的主机和端口。 因此，所有从Pushgateway抓取的指标都将Pushgateway的主机和端口作为`instance`标签和 `pushgateway`类似的`job`标签。
当推送到pushgateway的指标本身包含有`job`和 `instance` 标签时， pushgateway通过将指标的标签重命名为`exported_job`和`exported_instance`,解决与可能附加到推送网关的指标的标签的冲突。

然而，在收集目标的时候，我们常常不希望如此。 通常, 你会希望保留推送指标附带的 `job` and `instance`标签。 这就是在prometheus为pushgateway设置`honor_labels: true` 的原因。它启用了所需要的行为。 详见[documentation](https://prometheus.io/docs/operating/configuration/#scrape_config)

这有可能导致推送的指标没有`instance` 标签。 这种情况非常普遍，因为推送的指标通常处于服务级别，因此与特定实例无关。 即使 `honor_labels: true`时，如果指标中没有`instance`标签时，Prometheus服务将会附加一个`instance`标签。因此, 推送到pushgateway的指标如果没有`instance`标签 (并且分组关键字中也没有`instance`), Pushgateway将为这个指标导入一个空的`instance` (`{instance=""}`),等同于完全没有`instance`，但是会阻止服务器给他添加一个。

### About metric inconsistencies

Pushgateway 在 `/metrics` 接口暴露所有推送过来的指标和它自己的指标. (详见 [exposed metrics](#exposed-metrics) ) 因此，所有的指标必须保持一致: 有相同名字的指标必须类型相同, 即使他们被推送到不同的分组, 且不得重复, i.e. 有相同名字和完全相同的标签对。推送这种将会导致不一致，并且被决绝接收，返回 状态码404。pushgateway 将在info级别记录一条不一致的日志信息。

_Legacy note: The help string of Pushgateway's own `push_time_seconds` metric
has changed in v0.10.0. By using a persistence file, metrics pushed to a
Pushgateway of an earlier versions can make it into a Pushgateway of v0.10.0 or
later. In this case, the above mentioned log message will show up. Once each
previously pushed group has been deleted or received a new push, the log
message will disappear._

### About timestamps

If you push metrics at time *t*<sub>1</sub>, you might be tempted to believe
that Prometheus will scrape them with that same timestamp
*t*<sub>1</sub>. Instead, what Prometheus attaches as a timestamp is the time
when it scrapes the Pushgateway. Why so?

In the world view of Prometheus, a metric can be scraped at any
time. A metric that cannot be scraped has basically ceased to
exist. Prometheus is somewhat tolerant, but if it cannot get any
samples for a metric in 5min, it will behave as if that metric does
not exist anymore. Preventing that is actually one of the reasons to
use a Pushgateway. The Pushgateway will make the metrics of your
ephemeral job scrapable at any time. Attaching the time of pushing as
a timestamp would defeat that purpose because 5min after the last
push, your metric will look as stale to Prometheus as if it could not
be scraped at all anymore. (Prometheus knows only one timestamp per
sample, there is no way to distinguish a 'time of pushing' and a 'time
of scraping'.)

As there aren't any use cases where it would make sense to attach a
different timestamp, and many users attempting to incorrectly do so (despite no
client library supporting this), the Pushgateway rejects any pushes with
timestamps.

If you think you need to push a timestamp, please see [When To Use The
Pushgateway](https://prometheus.io/docs/practices/pushing/).

In order to make it easier to alert on failed pushers or those that have not
run recently, the Pushgateway will add in the metrics `push_time_seconds` and
`push_failure_time_seconds` with the Unix timestamp of the last successful and
failed `POST`/`PUT` to each group. This will override any pushed metric by that
name. A value of zero for either metric implies that the group has never seen a
successful or failed `POST`/`PUT`.

## API

All pushes are done via HTTP. The interface is vaguely REST-like.

### URL

The default port the push gateway is listening to is 9091. The path looks like

    /metrics/job/<JOB_NAME>{/<LABEL_NAME>/<LABEL_VALUE>}

`<JOB_NAME>` is used as the value of the `job` label, followed by any
number of other label pairs (which might or might not include an
`instance` label). The label set defined by the URL path is used as a
grouping key. Any of those labels already set in the body of the
request (as regular labels, e.g. `name{job="foo"} 42`)
_will be overwritten to match the labels defined by the URL path!_

If `job` or any label name is suffixed with `@base64`, the following job name
or label value is interpreted as a base64 encoded string according to [RFC
4648, using the URL and filename safe
alphabet](https://tools.ietf.org/html/rfc4648#section-5). (Padding is
optional.) This is the only way of using job names or label values that contain
a `/`. For other special characters, the usual URI component encoding works,
too, but the base64 might be more convenient.

Ideally, client libraries take care of the suffixing and encoding.

Examples:

* To use the grouping key `job="directory_cleaner",path="/var/tmp"`, the
  following path will _not_ work:

	  /metrics/job/directory_cleaner/path//var/tmp
	  
  Instead, use the base64 URL-safe encoding for the label value and mark it by
  suffixing the label name with `@base64`:
  
  	  /metrics/job/directory_cleaner/path@base64/L3Zhci90bXA
	  
  If you are not using a client library that handles the encoding for you, you
  can use encoding tools. For example, there is a command line tool `base64url`
  (Debian package `basez`), which you could combine with `curl` to push from
  the command line in the following way:
  
      echo 'some_metric{foo="bar"} 3.14' | curl --data-binary @- http://pushgateway.example.org:9091/metrics/job/directory_cleaner/path@base64/$(echo -n '/var/tmp' | base64url)
  
* The grouping key `job="titan",name="Προμηθεύς"` can be represented
  “traditionally” with URI encoding:
  
      /metrics/job/titan/name/%CE%A0%CF%81%CE%BF%CE%BC%CE%B7%CE%B8%CE%B5%CF%8D%CF%82
	  
  Or you can use the more compact base64 encoding:
  
      /metrics/job/titan/name@base64/zqDPgc6_zrzOt864zrXPjc-C

### `PUT` method

`PUT` is used to push a group of metrics. All metrics with the
grouping key specified in the URL are replaced by the metrics pushed
with `PUT`.

The body of the request contains the metrics to push either as delimited binary
protocol buffers or in the simple flat text format (both in version 0.0.4, see
the
[data exposition format specification](https://docs.google.com/document/d/1ZjyKiKxZV83VI9ZKAXRGKaUKK2BIWCT7oiGBKDBpjEY/edit?usp=sharing)).
Discrimination between the two variants is done via the `Content-Type`
header. (Use the value `application/vnd.google.protobuf;
proto=io.prometheus.client.MetricFamily; encoding=delimited` for protocol
buffers, otherwise the text format is tried as a fall-back.)

The response code upon success is either 200 or 400. A 200 response implies a
successful push, either replacing an existing group of metrics or creating a
new one. A 400 response can happen if the request is malformed or if the pushed
metrics are inconsistent with metrics pushed to other groups or collide with
metrics of the Pushgateway itself. An explanation is returned in the body of
the response and logged on error level.

In rare cases, it is possible that the Pushgateway ends up with an inconsistent
set of metrics already pushed. In that case, new pushes are also rejected as
inconsistent even if the culprit is metrics that were pushed earlier. Delete
the offending metrics to get out of that situation.

_If using the protobuf format, do not send duplicate MetricFamily
proto messages (i.e. more than one with the same name) in one push, as
they will overwrite each other._

Note that the Pushgateway doesn't provide any strong guarantees that the pushed
metrics are persisted to disk. (A server crash may cause data loss. Or the push
gateway is configured to not persist to disk at all.)

A `PUT` request with an empty body effectively deletes all metrics with the
specified grouping key. However, in contrast to the
[`DELETE` request](#delete-method) described below, it does update the
`push_time_seconds` metrics.

### `POST` method

`POST` works exactly like the `PUT` method but only metrics with the
same name as the newly pushed metrics are replaced (among those with
the same grouping key).

A `POST` request with an empty body merely updates the `push_time_seconds`
metrics but does not change any of the previously pushed metrics.

### `DELETE` method

`DELETE` is used to delete metrics from the push gateway. The request
must not contain any content. All metrics with the grouping key
specified in the URL are deleted.

The response code upon success is always 202. The delete
request is merely queued at that moment. There is no guarantee that the
request will actually be executed or that the result will make it to
the persistence layer (e.g. in case of a server crash). However, the
order of `PUT`/`POST` and `DELETE` request is guaranteed, i.e. if you
have successfully sent a `DELETE` request and then send a `PUT`, it is
guaranteed that the `DELETE` will be processed first (and vice versa).

Deleting a grouping key without metrics is a no-op and will not result
in an error.

## Admin API

The Admin API provides administrative access to the Pushgateway, and must be
explicitly enabled by setting `--web.enable-admin-api` flag.

### URL

The default port the Pushgateway is listening to is 9091. The path looks like:

    /api/<API_VERSION>/admin/<HANDLER>
    
 * Available endpoints:
 
| HTTP_METHOD| API_VERSION |  HANDLER | DESCRIPTION |
| :-------: |:-------------:| :-----:| :----- |
| PUT     | v1 | wipe |  Safely deletes all metrics from the Pushgateway. |


* For example to wipe all metrics from the Pushgateway:

        curl -X PUT http://pushgateway.example.org:9091/api/v1/admin/wipe
        
## Management API

The Pushgateway provides a set of management API to ease automation and integrations.

* Available endpoints:
 
| HTTP_METHOD |  PATH | DESCRIPTION |
| :-------: | :-----| :----- |
| GET    | /-/healthy |  Returns 200 whenever the Pushgateway is healthy. |
| GET    | /-/ready |  Returns 200 whenever the Pushgateway is ready to serve traffic. |

* The following endpoint is disabled by default and can be enabled via the `--web.enable-lifecycle` flag.

| HTTP_METHOD |  PATH | DESCRIPTION |
| :-------: | :-----| :----- |
| PUT    | /-/quit |  Triggers a graceful shutdown of Pushgateway. |

Alternatively, a graceful shutdown can be triggered by sending a `SIGTERM` to the Pushgateway process.

## Exposed metrics

The Pushgateway exposes the following metrics via the configured
`--web.telemetry-path` (default: `/metrics`):
- The pushed metrics.
- For each pushed group, a metric `push_time_seconds` and
  `push_failure_time_seconds` as explained above.
- The usual metrics provided by the [Prometheus Go client library](https://github.com/prometheus/client_golang), i.e.:
  - `process_...`
  - `go_...`
  - `promhttp_metric_handler_requests_...`
- A number of metrics specific to the Pushgateway, as documented by the example
  scrape below.

```
# HELP pushgateway_build_info A metric with a constant '1' value labeled by version, revision, branch, and goversion from which pushgateway was built.
# TYPE pushgateway_build_info gauge
pushgateway_build_info{branch="master",goversion="go1.10.2",revision="8f88ccb0343fc3382f6b93a9d258797dcb15f770",version="0.5.2"} 1
# HELP pushgateway_http_push_duration_seconds HTTP request duration for pushes to the Pushgateway.
# TYPE pushgateway_http_push_duration_seconds summary
pushgateway_http_push_duration_seconds{method="post",quantile="0.1"} 0.000116755
pushgateway_http_push_duration_seconds{method="post",quantile="0.5"} 0.000192608
pushgateway_http_push_duration_seconds{method="post",quantile="0.9"} 0.000327593
pushgateway_http_push_duration_seconds_sum{method="post"} 0.001622878
pushgateway_http_push_duration_seconds_count{method="post"} 8
# HELP pushgateway_http_push_size_bytes HTTP request size for pushes to the Pushgateway.
# TYPE pushgateway_http_push_size_bytes summary
pushgateway_http_push_size_bytes{method="post",quantile="0.1"} 166
pushgateway_http_push_size_bytes{method="post",quantile="0.5"} 182
pushgateway_http_push_size_bytes{method="post",quantile="0.9"} 196
pushgateway_http_push_size_bytes_sum{method="post"} 1450
pushgateway_http_push_size_bytes_count{method="post"} 8
# HELP pushgateway_http_requests_total Total HTTP requests processed by the Pushgateway, excluding scrapes.
# TYPE pushgateway_http_requests_total counter
pushgateway_http_requests_total{code="200",handler="static",method="get"} 5
pushgateway_http_requests_total{code="200",handler="status",method="get"} 8
pushgateway_http_requests_total{code="202",handler="delete",method="delete"} 1
pushgateway_http_requests_total{code="202",handler="push",method="post"} 6
pushgateway_http_requests_total{code="400",handler="push",method="post"} 2

```

### Alerting on failed pushes

It is in general a good idea to alert on `push_time_seconds` being much farther
behind than expected. This will catch both failed pushes as well as pushers
being down completely.

To detect failed pushes much earlier, alert on `push_failure_time_seconds >
push_time_seconds`.

Pushes can also fail because they are malformed. In this case, they never reach
any metric group and therefore won't set any `push_failure_time_seconds`
metrics. Those pushes are still counted as
`pushgateway_http_requests_total{code="400",handler="push"}`. You can alert on
the `rate` of this metric, but you have to inspect the logs to identify the
offending pusher.

## Development

The normal binary embeds the web files in the `resources` directory.
For development purposes, it is handy to have a running binary use
those files directly (so that you can see the effect of changes immediately).
To switch to direct usage, add `-tags dev` to the `flags` entry in
`.promu.yml`, and then `make build`. Switch back to "normal" mode by
reverting the changes to `.promu.yml` and typing `make assets`.

##  Contributing

Relevant style guidelines are the [Go Code Review
Comments](https://code.google.com/p/go-wiki/wiki/CodeReviewComments)
and the _Formatting and style_ section of Peter Bourgon's [Go:
Best Practices for Production
Environments](http://peter.bourgon.org/go-in-production/#formatting-and-style).

[travis]: https://travis-ci.org/prometheus/pushgateway
[hub]: https://hub.docker.com/r/prom/pushgateway/
[circleci]: https://circleci.com/gh/prometheus/pushgateway
[quay]: https://quay.io/repository/prometheus/pushgateway
