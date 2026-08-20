<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * The landing page.
 *
 * Rendered entirely server-side and on purpose: this is the skeleton that proves
 * Nextcloud can find, list and decode the mobile app's files. Introducing a
 * build step before that is demonstrated would mean debugging two things at once.
 * The Vue dashboard replaces this template in a later phase (DESIGN.md §15).
 *
 * @var array{overview: ?\OCA\Cairn\Service\Overview} $_
 * @var \OCP\IL10N $l
 */

use OCA\Cairn\Service\MetricOverview;
use OCA\Cairn\Service\Overview;

\OCP\Util::addStyle('cairn', 'cairn');

/** @var ?Overview $overview */
$overview = $_['overview'];
?>
<div id="cairn-app">
	<div class="cairn-sheet">
	<h2>Cairn</h2>
	<p class="cairn-subtitle">
		A read-only view of the health files in your own storage.
	</p>

<?php if ($overview === null || !$overview->hasRoot) { ?>
	<div class="cairn-empty-state">
		<p>
			<strong>No <code>Cairn</code> folder yet.</strong>
		</p>
		<p>
			The Cairn phone app writes your health data to a folder called
			<code>Cairn</code> at the top level of your files. Connect the app to
			this Nextcloud and run a sync, and this page will show what arrived.
		</p>
	</div>
<?php } else { ?>
	<?php $manifest = $overview->manifest; ?>
	<dl class="cairn-manifest">
		<div>
			<dt>Format version</dt>
			<dd class="cairn-value"><?php p($manifest === null ? '—' : (string)$manifest->formatVersion); ?></dd>
		</div>
		<div>
			<dt>Written by</dt>
			<dd class="cairn-value"><?php p($manifest?->generator ?? '—'); ?></dd>
		</div>
		<div>
			<dt>Last updated</dt>
			<dd class="cairn-value"><?php p($manifest?->updatedDateTime ?? '—'); ?></dd>
		</div>
		<div>
			<dt>Shard files</dt>
			<dd class="cairn-value"><?php p((string)$overview->totalShards()); ?></dd>
		</div>
	</dl>

	<div class="cairn-table-wrap">
		<table class="cairn-metrics">
			<thead>
				<tr>
					<th>Metric</th>
					<th class="cairn-numeric">Shards</th>
					<th>First day</th>
					<th>Last day</th>
					<th class="cairn-numeric">Datapoints in newest</th>
					<th class="cairn-numeric">Unreadable lines</th>
				</tr>
			</thead>
			<tbody>
<?php foreach ($overview->metrics as $metric) {
	/** @var MetricOverview $metric */
	$empty = $metric->shardCount === 0;
	?>
				<tr>
					<td><code><?php p($metric->metric->value); ?></code></td>
					<td class="cairn-numeric<?php p($empty ? ' cairn-empty' : ''); ?>"><?php p((string)$metric->shardCount); ?></td>
					<td class="<?php p($empty ? 'cairn-empty' : ''); ?>"><?php p($metric->firstDay ?? '—'); ?></td>
					<td class="<?php p($empty ? 'cairn-empty' : ''); ?>"><?php p($metric->lastDay ?? '—'); ?></td>
					<td class="cairn-numeric<?php p($empty ? ' cairn-empty' : ''); ?>"><?php p($empty ? '—' : (string)$metric->newestDatapoints); ?></td>
					<td class="cairn-numeric<?php p($metric->newestSkippedLines > 0 ? ' cairn-skipped' : ' cairn-empty'); ?>"><?php p($metric->newestSkippedLines > 0 ? (string)$metric->newestSkippedLines : '—'); ?></td>
				</tr>
<?php } ?>
			</tbody>
		</table>
	</div>

	<p class="cairn-note">
		&ldquo;Unreadable lines&rdquo; counts lines in the newest shard that could
		not be decoded &mdash; usually a single truncated line left by a sync that
		was interrupted mid-append. They are skipped, never repaired: this app only
		ever reads. A non-zero count here is informational, not an error.
	</p>
<?php } ?>
	</div>
</div>
