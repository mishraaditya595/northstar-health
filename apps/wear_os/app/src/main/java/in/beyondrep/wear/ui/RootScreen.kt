package `in`.beyondrep.wear.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavType
import androidx.navigation.navArgument
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController
import `in`.beyondrep.wear.core.glance.Metric
import kotlinx.coroutines.launch

/** The watch app: Home and Train as two vertical pages, detail screens pushed on top. */
@Composable
fun RootScreen(viewModel: WatchViewModel) {
    val ui by viewModel.ui.collectAsState()
    RootContent(ui)
}

@Composable
fun RootContent(ui: WatchUi, initialPage: Int = 0) {
    MaterialTheme {
        Box(Modifier.fillMaxSize().background(Palette.canvas)) {
            when (ui) {
                WatchUi.Loading -> Unit
                WatchUi.Unbound -> UnboundScreen()
                is WatchUi.Ready -> Browser(ui, initialPage)
            }
        }
    }
}

@Composable
private fun Browser(ui: WatchUi.Ready, initialPage: Int) {
    val nav = rememberSwipeDismissableNavController()
    SwipeDismissableNavHost(navController = nav, startDestination = Routes.PAGES) {
        composable(Routes.PAGES) {
            Pages(ui, initialPage, onOpen = { nav.navigate(it) })
        }
        composable(Routes.READINESS) { ReadinessDetailScreen(ui.glance) }
        composable(
            "${Routes.METRIC}/{metric}",
            arguments = listOf(navArgument("metric") { type = NavType.StringType }),
        ) { entry ->
            val metric = entry.arguments?.getString("metric")?.let { name -> Metric.entries.firstOrNull { it.name == name } }
            val detail = metric?.let { ui.details[it] }
            when {
                metric == null || detail == null -> NoDataScreen()
                metric == Metric.SLEEP -> SleepDetailScreen(detail)
                metric == Metric.STEPS -> TrendDetailScreen(detail, metric, ChartStyle.BARS)
                else -> TrendDetailScreen(detail, metric, ChartStyle.LINE)
            }
        }
        composable(Routes.SYNC) { SyncScreen(ui.sync, ui.waiting) }
        composable(Routes.TODAY) { PlanPreviewScreen(ui.previews[null]) }
        composable(
            "${Routes.PLAN}/{id}",
            arguments = listOf(navArgument("id") { type = NavType.StringType }),
        ) { entry -> PlanPreviewScreen(ui.previews[entry.arguments?.getString("id")]) }
    }
}

@Composable
private fun Pages(ui: WatchUi.Ready, initialPage: Int, onOpen: (String) -> Unit) {
    val pager = rememberPagerState(initialPage = initialPage, pageCount = { 2 })
    val scope = rememberCoroutineScope()
    Box(Modifier.fillMaxSize()) {
        VerticalPager(state = pager, modifier = Modifier.fillMaxSize()) { page ->
            if (page == 0) {
                HomeScreen(ui, onOpen = onOpen, onTrain = { scope.launch { pager.animateScrollToPage(1) } })
            } else {
                TrainScreen(ui, onOpenToday = { onOpen(Routes.TODAY) }, onOpenPlan = { onOpen(Routes.plan(it)) })
            }
        }
        // Two dots at the right edge show which page this is.
        Column(
            Modifier.align(Alignment.CenterEnd).padding(end = 4.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            for (i in 0 until 2) {
                Box(
                    Modifier.size(5.dp).background(
                        if (i == pager.currentPage) Palette.ink else Palette.secondary.copy(alpha = 0.4f), CircleShape,
                    ),
                )
            }
        }
    }
}
