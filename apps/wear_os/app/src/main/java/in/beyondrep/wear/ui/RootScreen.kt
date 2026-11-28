package `in`.beyondrep.wear.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.navigation.NavType
import androidx.navigation.navArgument
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController
import `in`.beyondrep.wear.core.glance.Metric
import `in`.beyondrep.wear.ui.workout.StartTarget
import `in`.beyondrep.wear.ui.workout.SummaryScreen
import `in`.beyondrep.wear.ui.workout.WorkoutActions
import `in`.beyondrep.wear.ui.workout.WorkoutScreen
import `in`.beyondrep.wear.ui.workout.WorkoutUi
import `in`.beyondrep.wear.ui.workout.rememberPermissionGate
import `in`.beyondrep.wear.workout.RunnerState
import kotlinx.coroutines.launch

/** The watch app: Home and Train as two vertical pages, detail screens pushed on top. */
@Composable
fun RootScreen(viewModel: WatchViewModel) {
    val ui by viewModel.ui.collectAsState()
    val runner by viewModel.workout.collectAsState()
    val now by viewModel.now.collectAsState()
    val revision by viewModel.revision.collectAsState()
    val ambient by viewModel.ambient.collectAsState()
    val status by viewModel.summaryStatus.collectAsState()
    val gate = rememberPermissionGate()
    // Start asks for the sensor permissions first (once); everything else goes straight through.
    val actions = remember(viewModel, gate) {
        object : WorkoutActions by viewModel {
            override fun start(target: StartTarget) = gate.afterPrompt { viewModel.start(target) }
        }
    }
    RootContent(ui, 0, WorkoutUi(runner, now, revision, ambient, status), actions)
}

@Composable
fun RootContent(
    ui: WatchUi,
    initialPage: Int = 0,
    workout: WorkoutUi = WorkoutUi.IDLE,
    actions: WorkoutActions = WorkoutActions.None,
) {
    MaterialTheme {
        Box(Modifier.fillMaxSize().background(Palette.canvas)) {
            val runner = workout.runner
            when {
                runner is RunnerState.Running -> WorkoutScreen(
                    runner, workout, unit = runner.unit,
                    recent = (ui as? WatchUi.Ready)?.recent.orEmpty(), actions = actions,
                )
                runner is RunnerState.Finished -> SummaryScreen(runner.summary, workout.summaryStatus, actions::dismiss)
                runner is RunnerState.Blocked -> BlockedScreen(runner.reason, actions::dismiss)
                ui == WatchUi.Loading -> Unit
                ui == WatchUi.Unbound -> UnboundScreen()
                ui is WatchUi.Ready -> Browser(ui, initialPage, actions)
            }
        }
    }
}

@Composable
private fun BlockedScreen(reason: String, onOk: () -> Unit) {
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item { BrText(reason, size = 13, align = TextAlign.Center, modifier = Modifier.fillMaxWidth(0.85f)) }
        item { BrButton("OK", onOk, Modifier.fillMaxWidth(0.85f), prominent = true) }
    }
}

@Composable
private fun Browser(ui: WatchUi.Ready, initialPage: Int, actions: WorkoutActions) {
    val nav = rememberSwipeDismissableNavController()
    SwipeDismissableNavHost(navController = nav, startDestination = Routes.PAGES) {
        composable(Routes.PAGES) {
            Pages(ui, initialPage, onOpen = { nav.navigate(it) }, onStart = actions::start)
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
        composable(Routes.TODAY) {
            PlanPreviewScreen(ui.previews[null], ui.previews[null]?.let { { actions.start(StartTarget.Today) } })
        }
        composable(
            "${Routes.PLAN}/{id}",
            arguments = listOf(navArgument("id") { type = NavType.StringType }),
        ) { entry ->
            val id = entry.arguments?.getString("id")
            PlanPreviewScreen(ui.previews[id], id?.takeIf { ui.previews[it] != null }?.let { { actions.start(StartTarget.Plan(it)) } })
        }
    }
}

@Composable
private fun Pages(ui: WatchUi.Ready, initialPage: Int, onOpen: (String) -> Unit, onStart: (StartTarget) -> Unit) {
    val pager = rememberPagerState(initialPage = initialPage, pageCount = { 2 })
    val scope = rememberCoroutineScope()
    Box(Modifier.fillMaxSize()) {
        VerticalPager(state = pager, modifier = Modifier.fillMaxSize()) { page ->
            if (page == 0) {
                HomeScreen(ui, onOpen = onOpen, onTrain = { scope.launch { pager.animateScrollToPage(1) } })
            } else {
                TrainScreen(
                    ui, onOpenToday = { onOpen(Routes.TODAY) }, onOpenPlan = { onOpen(Routes.plan(it)) },
                    onStart = onStart,
                )
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
