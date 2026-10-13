import Component from "@glimmer/component";
import { service } from "@ember/service";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";
import { profileLink } from "../../lib/client-rules";

export default class LearningProfileLink extends Component {
  @service siteSettings;
  get url() { return getURL(profileLink(this.args.model?.username || "")); }
  <template>
    {{#if this.siteSettings.blackroom_learning_enabled}}
      <div class="bl-profile-link"><dt>{{i18n "blackroom_learning.title"}}</dt><dd><a href={{this.url}}>{{i18n "blackroom_learning.view_user_progress"}}</a></dd></div>
    {{/if}}
  </template>
}
