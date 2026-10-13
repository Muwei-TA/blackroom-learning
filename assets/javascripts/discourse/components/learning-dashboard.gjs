import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";
import LearningGoalCard from "./learning-goal-card";
import LearningGoalForm from "./learning-goal-form";
import LearningCheckinForm from "./learning-checkin-form";
import { errorText } from "../lib/client-rules";

export default class LearningDashboard extends Component {
  @tracked override = null;
  @tracked overrideFor = null;
  @tracked busy = false;
  @tracked error = "";
  @tracked selectedGoalId = null;
  get data() { return this.overrideFor === this.args.model ? this.override || this.args.model : this.args.model; }
  get homeUrl() { return getURL("/learning"); }
  get hasActiveGoal() {
    return this.data.my_goals.some((goal) => goal.ends_on >= this.data.today && ["active", "scheduled", "awaiting_approval", "unavailable"].includes(goal.status));
  }
  get canCreate() { return this.data.can_create && !this.hasActiveGoal; }
  get selectedGoals() { return this.data.my_goals.filter((goal) => goal.id === this.selectedGoalId && goal.can_checkin); }
  get achievements() {
    return (this.data.summary?.achievements || []).map((code) => ({ code, label: i18n(`blackroom_learning.achievements.${code}`) }));
  }
  @action selectGoal(goal) { this.selectedGoalId = goal.id; }
  @action async refresh() {
    if (this.busy) { return; }
    this.busy = true; this.error = "";
    const model = this.args.model;
    try {
      const query = model.query || {};
      const result = await ajax("/learning/data.json", { data: query });
      if (!this.isDestroying && !this.isDestroyed && this.args.model === model) {
        this.overrideFor = model; this.override = { ...result, query };
      }
    } catch (error) {
      if (!this.isDestroying && !this.isDestroyed) { this.error = errorText(error, i18n("blackroom_learning.request_failed")); }
    } finally {
      if (!this.isDestroying && !this.isDestroyed) { this.busy = false; }
    }
  }
  @action async loadMore() {
    if (this.busy || this.data.next_page === null) { return; }
    this.busy = true; this.error = "";
    const model = this.args.model, previous = this.data;
    try {
      const result = await ajax("/learning/data.json", { data: { ...(model.query || {}), page: previous.next_page } });
      if (!this.isDestroying && !this.isDestroyed && this.args.model === model) {
        const goals = [...new Map([...previous.goals, ...result.goals].map((goal) => [goal.id, goal])).values()];
        this.overrideFor = model; this.override = { ...previous, goals, next_page: result.next_page };
      }
    } catch (error) {
      if (!this.isDestroying && !this.isDestroyed) { this.error = errorText(error, i18n("blackroom_learning.request_failed")); }
    } finally {
      if (!this.isDestroying && !this.isDestroyed) { this.busy = false; }
    }
  }
  @action async cancelGoal(goal) {
    if (this.busy || !window.confirm(i18n("blackroom_learning.confirm_end"))) { return; }
    this.busy = true; this.error = "";
    try { await ajax(`/learning/goals/${goal.id}/cancel.json`, { type: "POST" }); }
    catch (error) { if (!this.isDestroying && !this.isDestroyed) { this.error = errorText(error, i18n("blackroom_learning.request_failed")); } }
    finally { if (!this.isDestroying && !this.isDestroyed) { this.busy = false; } }
    if (!this.isDestroying && !this.isDestroyed && !this.error) { await this.refresh(); }
  }
  <template>
    <main class="bl-learning">
      <header class="bl-page-heading">
        <div><h1>{{i18n "blackroom_learning.title"}}</h1><p>{{i18n "blackroom_learning.subtitle"}}</p></div>
        <nav aria-label={{i18n "blackroom_learning.navigation"}}>
          <a href={{this.homeUrl}}>{{i18n "blackroom_learning.all_goals"}}</a>
          <a href={{this.data.flag_topic_url}}>{{i18n "blackroom_learning.flag_hall"}}</a>
          <button class="btn btn-default" type="button" disabled={{this.busy}} {{on "click" this.refresh}}>{{i18n "blackroom_learning.refresh"}}</button>
        </nav>
      </header>
      <p class="bl-hint">{{i18n "blackroom_learning.timezone_notice" today=this.data.today}}</p>
      {{#if this.error}}<p class="bl-error" role="alert">{{this.error}}</p>{{/if}}
      {{#if this.data.summary}}
        <section class="bl-summary" aria-label={{i18n "blackroom_learning.summary"}}>
          <h2>{{this.data.summary.username}}</h2>
          <p><strong>{{this.data.summary.learning_days}}</strong> {{i18n "blackroom_learning.real_days"}} · <strong>{{this.data.summary.xp}}</strong> XP · Lv.{{this.data.summary.level}}</p>
          <p>{{i18n "blackroom_learning.streak_label" current=this.data.summary.streak.current longest=this.data.summary.streak.longest}}</p>
          <div class="bl-achievements">{{#each this.achievements key="code" as |award|}}<span>{{award.label}}</span>{{/each}}</div>
        </section>
      {{/if}}
      {{#if this.canCreate}}
        <section class="bl-create"><h2>{{i18n "blackroom_learning.set_goal"}}</h2><LearningGoalForm @today={{this.data.today}} @onSaved={{this.refresh}} /></section>
      {{else if this.hasActiveGoal}}<p class="bl-hint">{{i18n "blackroom_learning.one_goal_notice"}}</p>{{/if}}
      {{#if this.data.my_goals.length}}
        <section><h2>{{i18n "blackroom_learning.my_goals"}}</h2>
          <div class="bl-goal-grid">{{#each this.data.my_goals key="id" as |goal|}}<LearningGoalCard @goal={{goal}} @today={{this.data.today}} @onCheckin={{this.selectGoal}} @onCancel={{this.cancelGoal}} />{{/each}}</div>
        </section>
      {{/if}}
      {{#each this.selectedGoals key="id" as |goal|}}<LearningCheckinForm @goal={{goal}} @onSaved={{this.refresh}} />{{/each}}
      <section><h2>{{i18n "blackroom_learning.goal_gallery"}}</h2>
        <div class="bl-goal-grid">{{#each this.data.goals key="id" as |goal|}}<LearningGoalCard @goal={{goal}} @today={{this.data.today}} @onCheckin={{this.selectGoal}} />{{else}}<p>{{i18n "blackroom_learning.empty"}}</p>{{/each}}</div>
        {{#if this.data.next_page}}<button class="btn btn-default" disabled={{this.busy}} type="button" {{on "click" this.loadMore}}>{{i18n "blackroom_learning.load_more"}}</button>{{/if}}
      </section>
    </main>
  </template>
}
