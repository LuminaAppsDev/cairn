/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import { createApp } from 'vue'
import App from './App.vue'

/*
 * Nextcloud renders the page shell and this takes over the body of it. There is
 * no router: the app is one screen over one folder, and a route would only add
 * a URL to keep in sync with nothing.
 */
createApp(App).mount('#cairn')
